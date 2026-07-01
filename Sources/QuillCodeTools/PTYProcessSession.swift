import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import CQuillPTY
import QuillCodeCore

/// The terminal window size (in character cells) applied to a PTY session so
/// programs that query the terminal — `stty size`, ncurses TUIs, pagers — lay
/// out against the workspace terminal's real dimensions.
public struct PTYWindowSize: Sendable, Hashable {
    public var rows: UInt16
    public var columns: UInt16

    public init(rows: UInt16, columns: UInt16) {
        self.rows = rows
        self.columns = columns
    }
}

/// Runs a command attached to a pseudo-terminal (PTY) so programs that probe
/// `isatty()` behave as they would in a real terminal — emitting colors, line
/// editing, and TUI control sequences instead of falling back to plain-pipe
/// output. This is the first concrete step of the "full PTY terminal sessions"
/// roadmap item and deliberately reuses the existing `ShellProcessEvent`
/// streaming contract so the workspace terminal can adopt it incrementally
/// without a new event type.
///
/// A PTY merges the child's stdout and stderr onto one terminal device, so
/// output is delivered on a single `.stdout` stream and the finished
/// `ToolResult` carries an empty `stderr`.
public final class PTYProcessSession: ShellInteractiveSession, @unchecked Sendable {
    public let events: AsyncStream<ShellProcessEvent>

    private let continuation: AsyncStream<ShellProcessEvent>.Continuation
    private let request: ShellExecutionRequest
    private let windowSize: PTYWindowSize?
    private let lock = NSLock()
    private var process: Process?
    private var masterFD: Int32 = -1
    private var output = ""
    private var didFinish = false
    private var didCancel = false
    private var didTimeOut = false
    private var didSuspend = false

    public init(request: ShellExecutionRequest, windowSize: PTYWindowSize? = nil) {
        self.request = request
        self.windowSize = windowSize
        let (stream, continuation) = AsyncStream<ShellProcessEvent>.makeStream()
        self.events = stream
        self.continuation = continuation
    }

    public func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run()
        }
    }

    public func cancel() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didCancel = true
        let activeProcess = process
        didSuspend = false
        lock.unlock()
        if let activeProcess {
            Self.terminate(activeProcess)
        }
    }

    /// Terminates `process`, always continuing it with `SIGCONT` first: a stopped process does not act
    /// on the `SIGTERM` from `terminate()` until it has been continued, so a suspended command would
    /// otherwise survive cancellation and time-outs. The `SIGCONT` is sent unconditionally because it
    /// is a harmless no-op on a running or already-reaped process — doing it every time immunizes all
    /// three terminate paths against a `suspend()` that races in after `didSuspend` was cleared, with no
    /// dependency on which guard flag happened to be set.
    ///
    /// Like `cancel()` before it, this signals only the session's direct child (`/bin/sh`); a pipeline
    /// or backgrounded grandchild in a separate process group is not covered. True process-group job
    /// control would require spawning the child as a group leader (`posix_spawn` with a new pgid), a
    /// larger change than this session's Foundation `Process` model — left for a follow-up.
    private static func terminate(_ process: Process) {
        kill(process.processIdentifier, SIGCONT)
        process.terminate()
    }

    /// Writes `text` to the terminal as if the user typed it, so interactive
    /// programs reading from the pty (shells, REPLs, prompts) can be driven.
    /// Returns `false` if the session has finished or has no live master fd.
    @discardableResult
    public func sendInput(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        lock.lock()
        let fd = masterFD
        let finished = didFinish
        lock.unlock()
        guard !finished, fd >= 0 else { return false }

        let bytes = Array(text.utf8)
        var written = 0
        while written < bytes.count {
            let count = bytes[written...].withUnsafeBytes { rawBuffer in
                write(fd, rawBuffer.baseAddress, rawBuffer.count)
            }
            guard count > 0 else { return false }
            written += count
        }
        return true
    }

    /// Applies a new terminal window size to a running session (e.g. when the
    /// user resizes the workspace terminal). Programs that handle `SIGWINCH` or
    /// re-query the size — shells, pagers, ncurses TUIs — pick up the change.
    /// Returns `false` if the session has finished or has no live master fd.
    @discardableResult
    public func resize(to windowSize: PTYWindowSize) -> Bool {
        lock.lock()
        let fd = masterFD
        let finished = didFinish
        lock.unlock()
        guard !finished, fd >= 0 else { return false }
        return cquill_pty_set_winsize(fd, windowSize.rows, windowSize.columns) == 0
    }

    /// Suspends the running command (terminal job control, like Ctrl+Z) by stopping its process with
    /// `SIGSTOP`. Returns `false` if the session has not started, has finished/cancelled, or is already
    /// suspended. `SIGSTOP` cannot be caught or ignored, so a successful send guarantees the process is
    /// stopped until `resume()`.
    @discardableResult
    public func suspend() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        // Refuse once any terminal intent is set (finish/cancel/timeout): together with the
        // unconditional SIGCONT in `terminate(_:)`, this closes the window where a suspend racing a
        // cancel/timeout could re-stop the process after it was continued for termination.
        guard !didFinish, !didCancel, !didTimeOut, !didSuspend, let process, process.isRunning else { return false }
        guard kill(process.processIdentifier, SIGSTOP) == 0 else { return false }
        didSuspend = true
        return true
    }

    /// Resumes a previously `suspend()`ed command by continuing its process with `SIGCONT`. Returns
    /// `false` if the session is not currently suspended (or has finished/cancelled).
    @discardableResult
    public func resume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard didSuspend, !didFinish, !didCancel, !didTimeOut, let process, process.isRunning else { return false }
        guard kill(process.processIdentifier, SIGCONT) == 0 else { return false }
        didSuspend = false
        return true
    }

    /// Whether the command is currently suspended.
    public var isSuspended: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didSuspend
    }

    private func run() {
        let trimmed = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish(exitCode: nil, ok: false, error: ShellToolMessages.missingCommand)
            return
        }

        // Allocate a pseudo-terminal master/slave pair. The POSIX pty helpers
        // live in a small C shim (`CQuillPTY`) because Swift's imported Glibc
        // module does not surface `posix_openpt`/`grantpt`/`unlockpt`/`ptsname`.
        var master: Int32 = -1
        var slave: Int32 = -1
        var slaveNameBuffer = [CChar](repeating: 0, count: 1024)
        let openResult = cquill_pty_open(&master, &slave, &slaveNameBuffer, slaveNameBuffer.count)
        guard openResult == 0 else {
            finish(exitCode: nil, ok: false, error: "Failed to allocate a pseudo-terminal.")
            return
        }

        // Apply the requested terminal dimensions before launching so the child
        // sees them from its first `stty size` / ncurses query.
        if let windowSize {
            _ = cquill_pty_set_winsize(master, windowSize.rows, windowSize.columns)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = request.cwd
        process.environment = ptyEnvironment(request.environment)

        // The child's stdin/stdout/stderr all point at the slave terminal device.
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = slaveHandle
        process.standardOutput = slaveHandle
        process.standardError = slaveHandle

        lock.lock()
        if didCancel {
            lock.unlock()
            close(master)
            close(slave)
            finishCancelled()
            return
        }
        lock.unlock()

        do {
            try process.run()
        } catch {
            close(master)
            close(slave)
            finish(exitCode: nil, ok: false, error: "Failed to start shell: \(error)")
            return
        }
        // The child holds its own duplicated slave descriptor; close the parent
        // copy so the master read returns EOF once the child exits.
        close(slave)

        lock.lock()
        self.process = process
        self.masterFD = master
        let shouldTerminate = didCancel
        lock.unlock()
        if shouldTerminate {
            process.terminate()
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + request.timeoutSeconds) { [weak self] in
            self?.timeout()
        }

        readMasterUntilEnd(master)
        process.waitUntilExit()
        close(master)
        finish(process: process)
    }

    private func readMasterUntilEnd(_ master: Int32) {
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                read(master, rawBuffer.baseAddress, bufferSize)
            }
            guard count > 0 else {
                // 0 = EOF; -1 = read error (e.g. EIO once the slave side closes).
                return
            }
            let text = String(decoding: buffer[0..<count], as: UTF8.self)
            handleOutput(text)
        }
    }

    private func handleOutput(_ text: String) {
        guard !text.isEmpty else { return }
        lock.lock()
        output += text
        lock.unlock()
        continuation.yield(.stdout(text))
    }

    private func timeout() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didTimeOut = true
        let activeProcess = process
        didSuspend = false
        lock.unlock()
        if let activeProcess {
            Self.terminate(activeProcess)
        }
    }

    private func ptyEnvironment(_ environment: [String: String]?) -> [String: String] {
        var resolved = environment ?? ProcessInfo.processInfo.environment
        if resolved["TERM"] == nil {
            resolved["TERM"] = "xterm-256color"
        }
        // Because this is a real PTY, commands see `isatty() == true` and launch their interactive
        // pager (git log/diff/branch/tag, man, systemctl, ...). The workspace terminal renders output
        // as scrollable text, not a full interactive screen, so a pager blocks the command waiting for
        // keypresses — it hangs until the timeout. The pane fundamentally cannot host an interactive
        // pager, so force a passthrough for every pager variable, OVERRIDING any inherited or captured
        // value (e.g. `PAGER=less` from the launching shell, or a prior in-pane `export PAGER=less`
        // persisted into the environment overrides) — respecting it would re-introduce the hang.
        // `MANPAGER` is set too because `man` consults it before `PAGER`.
        resolved["PAGER"] = "cat"
        resolved["GIT_PAGER"] = "cat"
        resolved["MANPAGER"] = "cat"
        return resolved
    }

    private func finish(process: Process) {
        let cancelled: Bool
        let timedOut: Bool
        lock.lock()
        cancelled = didCancel
        timedOut = didTimeOut
        lock.unlock()

        if cancelled {
            finish(exitCode: nil, ok: false, error: "Command cancelled.")
            return
        }
        if timedOut {
            finish(
                exitCode: process.terminationStatus,
                ok: false,
                error: "Command timed out after \(Int(request.timeoutSeconds))s."
            )
            return
        }
        let ok = process.terminationStatus == 0
        finish(
            exitCode: process.terminationStatus,
            ok: ok,
            error: ok ? nil : "Command failed with exit code \(process.terminationStatus)."
        )
    }

    private func finishCancelled() {
        finish(exitCode: nil, ok: false, error: "Command cancelled.")
    }

    private func finish(exitCode: Int32?, ok: Bool, error: String?) {
        let out: String
        let activeProcess: Process?
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        out = output
        activeProcess = process
        didSuspend = false
        process = nil
        masterFD = -1
        lock.unlock()

        if let activeProcess, activeProcess.isRunning {
            Self.terminate(activeProcess)
        }

        continuation.yield(.finished(ToolResult(
            ok: ok,
            stdout: out,
            stderr: "",
            exitCode: exitCode,
            error: error
        )))
        continuation.finish()
    }
}
