import Foundation
import QuillCodeCore

public struct ShellExecutionRequest: Sendable {
    public var command: String
    public var cwd: URL
    public var timeoutSeconds: TimeInterval

    public init(command: String, cwd: URL, timeoutSeconds: TimeInterval = 30) {
        self.command = command
        self.cwd = cwd
        self.timeoutSeconds = timeoutSeconds
    }
}

public struct ShellToolExecutor: Sendable {
    public init() {}

    public func run(_ request: ShellExecutionRequest) -> ToolResult {
        let trimmed = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ToolResult(ok: false, error: "No shell command was specified. Try `Run ls` or `Run df -h /`.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-lc", trimmed]
        process.currentDirectoryURL = request.cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ToolResult(ok: false, error: "Failed to start shell: \(error)")
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + request.timeoutSeconds) == .timedOut {
            process.terminate()
            return ToolResult(ok: false, error: "Command timed out after \(Int(request.timeoutSeconds))s.")
        }

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

public extension ToolDefinition {
    static let shellRun = ToolDefinition(
        name: "host.shell.run",
        description: "Run a shell command in the current project workspace.",
        parametersJSON: #"{"type":"object","properties":{"cmd":{"type":"string"},"cwd":{"type":"string"}},"required":["cmd"]}"#,
        host: .local,
        risk: .destructive
    )
}
