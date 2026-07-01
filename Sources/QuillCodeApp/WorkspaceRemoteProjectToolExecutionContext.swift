import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteProjectToolExecutionContext: Sendable {
    var connection: ProjectConnection
    var executor: SSHRemoteShellExecutor

    func run(
        command: String,
        connection overrideConnection: ProjectConnection? = nil
    ) -> ToolResult {
        guard let request = executor.request(
            command: command,
            connection: overrideConnection ?? connection
        ) else {
            return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
        }
        return ShellToolExecutor().run(request)
    }
}
