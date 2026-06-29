import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import QuillCodeCore

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
public final class PTYProcessSession: @unchecked Sendable {
    public let events: AsyncStream<ShellProcessEvent>

    private let continuation: AsyncStream<ShellProcessEvent>.Continuation
    private let request: ShellExecutionRequest
    private let lock = NSLock()
    private var process: Process?
    private var output = ""
    private var didFinish = false
    private var didCancel = false
    private var didTimeOut = false

    public init(request: ShellExecutionRequest) {
        self.request = request
        var capturedContinuation: AsyncStream<ShellProcessEvent>.Continuation!
        self.events = AsyncStream { capturedContinuation = $0 }
        self.continuation = capturedContinuation
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
        lock.unlock()
        activeProcess?.terminate()
    }

    private func run() {
        let trimmed = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish(exitCode: nil, ok: false, error: ShellToolMessages.missingCommand)
            return
        }

        // Allocate a pseudo-terminal master/slave pair using portable POSIX calls
        // (avoiding `openpty`, whose module exposure differs across platforms).
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let slaveNamePointer = ptsname(master) else {
            if master >= 0 { close(master) }
            finish(exitCode: nil, ok: false, error: "Failed to allocate a pseudo-terminal.")
            return
        }
        let slavePath = String(cString: slaveNamePointer)
        let slave = open(slavePath, O_RDWR | O_NOCTTY)
        guard slave >= 0 else {
            close(master)
            finish(exitCode: nil, ok: false, error: "Failed to open the pseudo-terminal slave.")
            return
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
        lock.unlock()
        activeProcess?.terminate()
    }

    private func ptyEnvironment(_ environment: [String: String]?) -> [String: String] {
        var resolved = environment ?? ProcessInfo.processInfo.environment
        if resolved["TERM"] == nil {
            resolved["TERM"] = "xterm-256color"
        }
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
        process = nil
        lock.unlock()

        if let activeProcess, activeProcess.isRunning {
            activeProcess.terminate()
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
