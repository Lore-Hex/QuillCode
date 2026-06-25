import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

struct WorkspaceAgentSendSessionFactory: Sendable {
    private let selectedProject: ProjectRef?
    private let browser: BrowserState
    private let browserToolOverride: AgentToolExecutionOverride?
    private let computerUseBackend: (any ComputerUseBackend)?
    private let globalMemoryDirectory: URL?
    private let mcpToolDefinitions: [ToolDefinition]
    private let mcpToolExecutionOverride: AgentToolExecutionOverride?
    private let sshRemoteShellExecutor: SSHRemoteShellExecutor

    init(
        selectedProject: ProjectRef?,
        browser: BrowserState,
        browserToolOverride: AgentToolExecutionOverride? = nil,
        computerUseBackend: (any ComputerUseBackend)?,
        globalMemoryDirectory: URL?,
        mcpToolDefinitions: [ToolDefinition],
        mcpToolExecutionOverride: AgentToolExecutionOverride?,
        sshRemoteShellExecutor: SSHRemoteShellExecutor
    ) {
        self.selectedProject = selectedProject
        self.browser = browser
        self.browserToolOverride = browserToolOverride
        self.computerUseBackend = computerUseBackend
        self.globalMemoryDirectory = globalMemoryDirectory
        self.mcpToolDefinitions = mcpToolDefinitions
        self.mcpToolExecutionOverride = mcpToolExecutionOverride
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
    }

    func makeSession(
        prompt: String,
        thread: ChatThread,
        runner: AgentRunner,
        workspaceRoot: URL
    ) -> WorkspaceAgentSendSession {
        WorkspaceAgentSendSession(
            prompt: prompt,
            thread: thread,
            runner: configuredRunner(from: runner),
            workspaceRoot: workspaceRoot
        )
    }

    private func configuredRunner(from runner: AgentRunner) -> AgentRunner {
        WorkspaceAgentRunContextBuilder(
            selectedProject: selectedProject,
            browser: browser,
            browserToolOverride: browserToolOverride,
            computerUseBackend: computerUseBackend,
            globalMemoryDirectory: globalMemoryDirectory,
            mcpToolDefinitions: mcpToolDefinitions,
            mcpToolExecutionOverride: mcpToolExecutionOverride,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        ).configuredRunner(from: runner)
    }
}
