import Foundation
import QuillCodeCore

public struct GitToolExecutor: Sendable {
    private let shell: ShellToolExecutor

    public init(shell: ShellToolExecutor = ShellToolExecutor()) {
        self.shell = shell
    }

    public func status(cwd: URL) -> ToolResult {
        shell.run(.init(command: "git status --short --branch", cwd: cwd, timeoutSeconds: 15))
    }

    public func diff(cwd: URL, staged: Bool = false) -> ToolResult {
        shell.run(.init(command: staged ? "git diff --staged" : "git diff", cwd: cwd, timeoutSeconds: 20))
    }
}

public extension ToolDefinition {
    static let gitStatus = ToolDefinition(
        name: "host.git.status",
        description: "Show git status for the project.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .local,
        risk: .read
    )

    static let gitDiff = ToolDefinition(
        name: "host.git.diff",
        description: "Show git diff for the project.",
        parametersJSON: #"{"type":"object","properties":{"staged":{"type":"boolean"}}}"#,
        host: .local,
        risk: .read
    )
}
