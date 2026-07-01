import Foundation
import QuillCodeCore

private enum ShellToolDefinitionSchema {
    static let run = #"""
    {"type":"object","properties":{"cmd":{"type":"string"},"cwd":{"type":"string","description":"Optional workspace-relative working directory. It must resolve inside the current project."},"timeoutSeconds":{"type":"integer","minimum":1,"maximum":1800,"description":"Optional bounded timeout in seconds."},"environment":{"type":"object","additionalProperties":{"type":"string"},"description":"Optional command-local environment overrides. Keys must be ASCII identifiers; values must be single-line strings."}},"required":["cmd"]}
    """#
}

public struct ShellExecutionRequest: Sendable {
    public var command: String
    public var cwd: URL
    public var timeoutSeconds: TimeInterval
    public var environment: [String: String]?

    public init(
        command: String,
        cwd: URL,
        timeoutSeconds: TimeInterval = 30,
        environment: [String: String]? = nil
    ) {
        self.command = command
        self.cwd = cwd
        self.timeoutSeconds = timeoutSeconds
        self.environment = environment
    }
}

public enum ShellProcessEvent: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    case finished(ToolResult)
}

public protocol ShellInteractiveSession: AnyObject, Sendable {
    var events: AsyncStream<ShellProcessEvent> { get }

    @discardableResult
    func sendInput(_ text: String) -> Bool

    @discardableResult
    func resize(to windowSize: PTYWindowSize) -> Bool

    func cancel()

    /// Suspends the running command (terminal job control). Returns `false` if unsupported or not
    /// applicable. Default: unsupported.
    @discardableResult
    func suspend() -> Bool

    /// Resumes a suspended command. Returns `false` if unsupported or not currently suspended.
    @discardableResult
    func resume() -> Bool

    /// Whether the command is currently suspended.
    var isSuspended: Bool { get }
}

public extension ShellInteractiveSession {
    // Job control is a PTY capability; pipe-backed and remote sessions do not support it, so they
    // inherit these no-ops and report "not suspended".
    @discardableResult
    func suspend() -> Bool { false }

    @discardableResult
    func resume() -> Bool { false }

    var isSuspended: Bool { false }
}

public final class ShellStreamingSession: ShellInteractiveSession, @unchecked Sendable {
    public let events: AsyncStream<ShellProcessEvent>
    private let runner: ShellStreamingProcessRunner

    init(request: ShellExecutionRequest) {
        let (stream, continuation) = AsyncStream<ShellProcessEvent>.makeStream()
        let runner = ShellStreamingProcessRunner(request: request, continuation: continuation)
        continuation.onTermination = { @Sendable _ in
            runner.cancel()
        }
        self.events = stream
        self.runner = runner
        runner.start()
    }

    @discardableResult
    public func sendInput(_ text: String) -> Bool {
        runner.sendInput(text)
    }

    @discardableResult
    public func resize(to windowSize: PTYWindowSize) -> Bool {
        false
    }

    public func cancel() {
        runner.cancel()
    }
}

enum ShellToolMessages {
    static let missingCommand = "No shell command was specified. Try `Run ls` or `Run df -h /`."
}

public struct ShellToolExecutor: Sendable {
    public init() {}

    public func run(_ request: ShellExecutionRequest) -> ToolResult {
        Self.runProcess(request)
    }

    public func runCancellable(_ request: ShellExecutionRequest) async -> ToolResult {
        let processBox = CancellableProcessBox()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.runProcess(request, processBox: processBox))
                }
            }
        } onCancel: {
            processBox.cancel()
        }

        if Task.isCancelled {
            return ToolResult(ok: false, error: "Command cancelled.")
        }
        return result
    }

    public func runStreaming(_ request: ShellExecutionRequest) -> AsyncStream<ShellProcessEvent> {
        startStreamingSession(request).events
    }

    public func startStreamingSession(_ request: ShellExecutionRequest) -> ShellStreamingSession {
        ShellStreamingSession(request: request)
    }

    private static func runProcess(
        _ request: ShellExecutionRequest,
        processBox: CancellableProcessBox? = nil
    ) -> ToolResult {
        let trimmed = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolResult(ok: false, error: ShellToolMessages.missingCommand)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = request.cwd
        process.environment = request.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            if processBox?.set(process) == false {
                return ToolResult(ok: false, error: "Command cancelled.")
            }
            try process.run()
        } catch {
            processBox?.clear()
            return ToolResult(ok: false, error: "Failed to start shell: \(error)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + request.timeoutSeconds) == .timedOut {
            process.terminate()
            processBox?.clear()
            return ToolResult(ok: false, error: "Command timed out after \(Int(request.timeoutSeconds))s.")
        }
        processBox?.clear()

        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let ok = process.terminationStatus == 0
        return ToolResult(
            ok: ok,
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            error: ok ? nil : "Command failed with exit code \(process.terminationStatus)."
        )
    }
}

private final class CancellableProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var shouldCancel = false

    func set(_ process: Process) -> Bool {
        lock.lock()
        if shouldCancel {
            lock.unlock()
            return false
        }
        self.process = process
        lock.unlock()
        return true
    }

    func cancel() {
        lock.lock()
        shouldCancel = true
        let activeProcess = process
        lock.unlock()
        activeProcess?.terminate()
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}

public extension ToolDefinition {
    static let shellRun = ToolDefinition(
        name: "host.shell.run",
        description: "Run a shell command in the current project workspace.",
        parametersJSON: ShellToolDefinitionSchema.run,
        host: .local,
        risk: .destructive
    )
}
