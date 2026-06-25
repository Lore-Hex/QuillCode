import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

struct WorkspaceAgentSendSessionFactory: Sendable {
    var baseRunner: AgentRunner
    var selectedProject: ProjectRef?
    var browser: BrowserState
    var browserToolOverride: AgentToolExecutionOverride?
    var computerUseBackend: (any ComputerUseBackend)?
    var globalMemoryDirectory: URL?
    var mcpToolDefinitions: [ToolDefinition]
    var mcpToolExecutionOverride: AgentToolExecutionOverride?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor
    var workspaceRoot: URL

    func makeSession(prompt: String, thread: ChatThread) -> WorkspaceAgentSendSession {
        WorkspaceAgentSendSession(
            prompt: prompt,
            thread: thread,
            runner: configuredRunner,
            workspaceRoot: workspaceRoot
        )
    }

    var configuredRunner: AgentRunner {
        WorkspaceAgentRunContextBuilder(
            selectedProject: selectedProject,
            browser: browser,
            browserToolOverride: browserToolOverride,
            computerUseBackend: computerUseBackend,
            globalMemoryDirectory: globalMemoryDirectory,
            mcpToolDefinitions: mcpToolDefinitions,
            mcpToolExecutionOverride: mcpToolExecutionOverride,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        ).configuredRunner(from: baseRunner)
    }
}
