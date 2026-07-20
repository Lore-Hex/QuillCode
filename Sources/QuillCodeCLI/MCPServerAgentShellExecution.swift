import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

extension MCPServerSession {
    func configureShellExecution(
        on runner: AgentRunner,
        record: AppServerThreadRecord,
        requestID: MCPServerRequestID
    ) -> AgentRunner {
        var configured = runner
        let inherited = configured.threadToolExecutionOverride
        configured.threadToolExecutionOverride = { [weak self] call, workspaceRoot, thread, progress in
            guard call.name == ToolDefinition.shellRun.name else {
                return await inherited?(call, workspaceRoot, thread, progress)
            }
            guard let self else {
                return AgentThreadToolExecution(
                    thread: thread,
                    result: ToolResult(ok: false, error: "The MCP session disconnected.")
                )
            }
            return await self.executeShell(
                call,
                thread: thread,
                workspaceRoot: workspaceRoot,
                settings: record.settings,
                requestID: requestID
            )
        }
        return configured
    }

    private func executeShell(
        _ call: ToolCall,
        thread: ChatThread,
        workspaceRoot: URL,
        settings: AppServerThreadSettings,
        requestID: MCPServerRequestID
    ) async -> AgentThreadToolExecution {
        let sandboxed = await ToolRouter(
            workspaceRoot: workspaceRoot,
            accessScope: .workspaceOnly,
            shell: ShellToolExecutor(sandboxPolicy: shellSandboxPolicy(
                settings.sandbox,
                workspaceRoot: workspaceRoot
            )),
            editGuard: .session(for: thread.id)
        ).executeCancellable(call)

        guard sandboxed.failureKind == .sandboxDenied,
              settings.approvalPolicy.stringValue == MCPServerApprovalPolicy.onFailure.rawValue,
              settings.approvalsReviewer == "user"
        else {
            return AgentThreadToolExecution(thread: thread, result: sandboxed)
        }

        let approval = await requestApproval(
            for: call,
            reason: "The command was blocked by the workspace sandbox. Retry once without it?",
            thread: thread,
            workspaceRoot: workspaceRoot,
            originatingRequestID: requestID
        )
        guard approval.decision == .allow else {
            var denied = sandboxed
            if case .deny(let reason) = approval.decision {
                denied.error = reason
            }
            return AgentThreadToolExecution(thread: thread, result: denied)
        }

        let retried = await ToolRouter(
            workspaceRoot: workspaceRoot,
            accessScope: .workspaceOnly,
            shell: ShellToolExecutor(),
            editGuard: .session(for: thread.id)
        ).executeCancellable(call)
        return AgentThreadToolExecution(thread: thread, result: retried)
    }

    private func shellSandboxPolicy(
        _ mode: CLISandboxMode,
        workspaceRoot: URL
    ) -> ShellProcessSandboxPolicy? {
        switch mode {
        case .readOnly:
            ShellProcessSandboxPolicy(mode: .readOnly)
        case .workspaceWrite:
            ShellProcessSandboxPolicy(
                mode: .workspaceWrite,
                writableRoots: [workspaceRoot]
            )
        case .dangerFullAccess:
            nil
        }
    }
}
