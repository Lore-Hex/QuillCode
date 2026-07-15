import Foundation
import QuillCodeCore

public struct GitProcessRunner: Sendable {
    private let githubCLIExecutable: URL?

    public init(githubCLIExecutable: URL? = nil) {
        self.githubCLIExecutable = githubCLIExecutable
    }

    public func runGit(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git"] + arguments,
            cwd: cwd,
            timeoutSeconds: timeoutSeconds,
            toolName: "Git"
        )
    }

    public func runGitHub(_ arguments: [String], cwd: URL, timeoutSeconds: TimeInterval) -> ToolResult {
        if let githubCLIExecutable {
            return runProcess(
                executableURL: githubCLIExecutable,
                arguments: arguments,
                cwd: cwd,
                timeoutSeconds: timeoutSeconds,
                toolName: "GitHub CLI"
            )
        }
        return runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["gh"] + arguments,
            cwd: cwd,
            timeoutSeconds: timeoutSeconds,
            toolName: "GitHub CLI"
        )
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        cwd: URL,
        timeoutSeconds: TimeInterval,
        toolName: String
    ) -> ToolResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let completionWaiter = ProcessCompletionWaiter(process: process)

        do {
            try process.run()
        } catch {
            return ToolResult(ok: false, error: "Failed to start \(toolName.lowercased()): \(error)")
        }

        let output = ProcessOutputCollector(stdout: stdout, stderr: stderr)
        output.start()
        if completionWaiter.wait(for: process, timeoutSeconds: timeoutSeconds) == .timedOut {
            output.wait()
            return ToolResult(ok: false, error: "\(toolName) command timed out after \(Int(timeoutSeconds))s.")
        }
        output.wait()

        let out = String(decoding: output.stdout, as: UTF8.self)
        let err = String(decoding: output.stderr, as: UTF8.self)
        let ok = process.terminationStatus == 0
        return ToolResult(
            ok: ok,
            stdout: out,
            stderr: err,
            exitCode: process.terminationStatus,
            error: ok ? nil : "\(toolName) command failed with exit code \(process.terminationStatus)."
        )
    }
}
