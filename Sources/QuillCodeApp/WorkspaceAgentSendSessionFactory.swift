import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

struct WorkspaceAgentSendSessionFactory: Sendable {
    private let baseRunner: AgentRunner
    private let selectedProject: ProjectRef?
    private let browser: BrowserState
    private let browserToolOverride: AgentToolExecutionOverride?
    private let computerUseBackend: (any ComputerUseBackend)?
    private let globalMemoryDirectory: URL?
    private let mcpToolDefinitions: [ToolDefinition]
    private let mcpToolExecutionOverride: AgentToolExecutionOverride?
    private let sshRemoteShellExecutor: SSHRemoteShellExecutor
    private let workspaceRoot: URL

    init(
        baseRunner: AgentRunner,
        selectedProject: ProjectRef?,
        browser: BrowserState,
        browserToolOverride: AgentToolExecutionOverride?,
        computerUseBackend: (any ComputerUseBackend)?,
        globalMemoryDirectory: URL?,
        mcpToolDefinitions: [ToolDefinition],
        mcpToolExecutionOverride: AgentToolExecutionOverride?,
        sshRemoteShellExecutor: SSHRemoteShellExecutor,
        workspaceRoot: URL
    ) {
        self.baseRunner = baseRunner
        self.selectedProject = selectedProject
        self.browser = browser
        self.browserToolOverride = browserToolOverride
        self.computerUseBackend = computerUseBackend
        self.globalMemoryDirectory = globalMemoryDirectory
        self.mcpToolDefinitions = mcpToolDefinitions
        self.mcpToolExecutionOverride = mcpToolExecutionOverride
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
        self.workspaceRoot = workspaceRoot
    }

    func makeSession(prompt: String, thread: ChatThread) -> WorkspaceAgentSendSession {
        WorkspaceAgentSendSession(
            prompt: prompt,
            thread: thread,
            runner: configuredRunner,
            workspaceRoot: workspaceRoot
        )
    }

    private var configuredRunner: AgentRunner {
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
