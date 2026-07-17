import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteProjectToolExecutionContext: Sendable {
    var connection: ProjectConnection
    var executor: SSHRemoteShellExecutor

    func run(
        command: String,
        connection overrideConnection: ProjectConnection? = nil,
        timeoutSeconds: TimeInterval = 60
    ) -> ToolResult {
        guard let request = executor.request(
            command: command,
            connection: overrideConnection ?? connection,
            timeoutSeconds: timeoutSeconds
        ) else {
            return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
        }
        return ShellToolExecutor().run(request)
    }

    func run(_ plan: WorkspaceRemoteProjectCommandPlan) -> ToolResult {
        plan.finalize(run(
            command: plan.command,
            connection: plan.connection,
            timeoutSeconds: plan.timeoutSeconds
        ))
    }
}
