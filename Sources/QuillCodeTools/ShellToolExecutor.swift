import Foundation
import QuillCodeCore

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

private enum ShellToolMessages {
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
        AsyncStream { continuation in
            let runner = StreamingShellProcess(request: request, continuation: continuation)
            continuation.onTermination = { @Sendable _ in
                runner.cancel()
            }
            runner.start()
        }
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

private final class StreamingShellProcess: @unchecked Sendable {
    private let request: ShellExecutionRequest
    private let continuation: AsyncStream<ShellProcessEvent>.Continuation
    private let lock = NSLock()
    private var process: Process?
    private var stdout = ""
    private var stderr = ""
    private var didFinish = false
    private var didCancel = false
    private var didTimeOut = false

    init(
        request: ShellExecutionRequest,
        continuation: AsyncStream<ShellProcessEvent>.Continuation
    ) {
        self.request = request
        self.continuation = continuation
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run()
        }
    }

    func cancel() {
        let activeProcess: Process?
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didCancel = true
        activeProcess = process
        lock.unlock()
        activeProcess?.terminate()
    }

    private func run() {
        let trimmed = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            finish(
                stdout: "",
                stderr: "",
                exitCode: nil,
                ok: false,
                error: ShellToolMessages.missingCommand
            )
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = request.cwd
        process.environment = request.environment

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        standardOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(handle.availableData, stream: .stdout)
        }
        standardError.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.handleOutput(handle.availableData, stream: .stderr)
        }
        process.terminationHandler = { [weak self] process in
            self?.finish(process: process)
        }

        lock.lock()
        if didCancel {
            lock.unlock()
            finishCancelled()
            return
        }
        self.process = process
        lock.unlock()

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardError.fileHandleForReading.readabilityHandler = nil
            finish(
                stdout: "",
                stderr: "",
                exitCode: nil,
                ok: false,
                error: "Failed to start shell: \(error)"
            )
            return
        }

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + request.timeoutSeconds) { [weak self] in
            self?.timeout()
        }
    }

    private enum OutputStream {
        case stdout
        case stderr
    }

    private func handleOutput(_ data: Data, stream: OutputStream) {
        guard !data.isEmpty else { return }
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        switch stream {
        case .stdout:
            stdout += text
        case .stderr:
            stderr += text
        }
        lock.unlock()
        switch stream {
        case .stdout:
            continuation.yield(.stdout(text))
        case .stderr:
            continuation.yield(.stderr(text))
        }
    }

    private func timeout() {
        let activeProcess: Process?
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didTimeOut = true
        activeProcess = process
        lock.unlock()
        activeProcess?.terminate()
    }

    private func finish(process: Process) {
        let outputPipe = process.standardOutput as? Pipe
        let errorPipe = process.standardError as? Pipe
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        if let output = outputPipe {
            handleOutput(output.fileHandleForReading.readDataToEndOfFile(), stream: .stdout)
        }
        if let error = errorPipe {
            handleOutput(error.fileHandleForReading.readDataToEndOfFile(), stream: .stderr)
        }

        let out: String
        let err: String
        let cancelled: Bool
        let timedOut: Bool
        lock.lock()
        out = stdout
        err = stderr
        cancelled = didCancel
        timedOut = didTimeOut
        lock.unlock()

        if cancelled {
            finish(stdout: out, stderr: err, exitCode: nil, ok: false, error: "Command cancelled.")
            return
        }
        if timedOut {
            finish(
                stdout: out,
                stderr: err,
                exitCode: process.terminationStatus,
                ok: false,
                error: "Command timed out after \(Int(request.timeoutSeconds))s."
            )
            return
        }

        let ok = process.terminationStatus == 0
        finish(
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            ok: ok,
            error: ok ? nil : "Command failed with exit code \(process.terminationStatus)."
        )
    }

    private func finishCancelled() {
        let out: String
        let err: String
        lock.lock()
        out = stdout
        err = stderr
        lock.unlock()
        finish(stdout: out, stderr: err, exitCode: nil, ok: false, error: "Command cancelled.")
    }

    private func finish(
        stdout: String,
        stderr: String,
        exitCode: Int32?,
        ok: Bool,
        error: String?
    ) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        let activeProcess = process
        process = nil
        lock.unlock()

        if let activeProcess {
            (activeProcess.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (activeProcess.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        }

        continuation.yield(.finished(ToolResult(
            ok: ok,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            error: error
        )))
        continuation.finish()
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
        parametersJSON: #"{"type":"object","properties":{"cmd":{"type":"string"},"cwd":{"type":"string"}},"required":["cmd"]}"#,
        host: .local,
        risk: .destructive
    )
}
