import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
import QuillComputerUseKit

struct WorkspaceAgentSendSessionFactory: Sendable {
    private let baseRunner: AgentRunner
    private let selectedProject: ProjectRef?
    private let config: AppConfig
    private let modelCatalog: [ModelInfo]
    private let spendPeriodThreads: [ChatThread]
    private let browser: BrowserState
    private let browserToolOverride: AgentToolExecutionOverride?
    private let computerUseBackend: (any ComputerUseBackend)?
    private let globalMemoryDirectory: URL?
    private let mcpToolDefinitions: [ToolDefinition]
    private let mcpToolExecutionOverride: AgentToolExecutionOverride?
    private let sshRemoteShellExecutor: SSHRemoteShellExecutor
    private let permissionRules: (any PermissionRulesProviding)?
    private let workspaceRoot: URL

    init(
        baseRunner: AgentRunner,
        selectedProject: ProjectRef?,
        config: AppConfig,
        modelCatalog: [ModelInfo] = [],
        spendPeriodThreads: [ChatThread] = [],
        browser: BrowserState,
        browserToolOverride: AgentToolExecutionOverride?,
        computerUseBackend: (any ComputerUseBackend)?,
        globalMemoryDirectory: URL?,
        mcpToolDefinitions: [ToolDefinition],
        mcpToolExecutionOverride: AgentToolExecutionOverride?,
        sshRemoteShellExecutor: SSHRemoteShellExecutor,
        permissionRules: (any PermissionRulesProviding)? = nil,
        workspaceRoot: URL
    ) {
        self.baseRunner = baseRunner
        self.selectedProject = selectedProject
        self.config = config
        self.modelCatalog = modelCatalog
        self.spendPeriodThreads = spendPeriodThreads
        self.browser = browser
        self.browserToolOverride = browserToolOverride
        self.computerUseBackend = computerUseBackend
        self.globalMemoryDirectory = globalMemoryDirectory
        self.mcpToolDefinitions = mcpToolDefinitions
        self.mcpToolExecutionOverride = mcpToolExecutionOverride
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
        self.permissionRules = permissionRules
        self.workspaceRoot = workspaceRoot
    }

    func makeSession(
        prompt: String,
        thread: ChatThread,
        recordsUserMessage: Bool = true
    ) -> WorkspaceAgentSendSession {
        WorkspaceAgentSendSession(
            prompt: prompt,
            thread: thread,
            // Pin this run to the THREAD's selected model so a `/model` switch (popup, typed, or
            // top-bar picker) takes effect on the next turn without a Settings save/re-sign-in, and
            // so each thread runs on its own model.
            runner: configuredRunner(modelID: thread.model),
            workspaceRoot: workspaceRoot,
            recordsUserMessage: recordsUserMessage,
            runHooks: selectedProject?.isRemote == true ? [] : (selectedProject?.runHooks ?? [])
        )
    }

    /// Builds the per-send runner, retargeting its LLM client at `modelID` (the thread's model).
    /// Internal (not private) so tests can assert the run path actually points at the selected
    /// model — the run-path is the load-bearing part of `/model`, not the persisted field alone.
    func configuredRunner(modelID: String?) -> AgentRunner {
        var runner = WorkspaceAgentRunContextBuilder(
            selectedProject: selectedProject,
            config: config,
            modelCatalog: modelCatalog,
            spendPeriodThreads: spendPeriodThreads,
            browser: browser,
            browserToolOverride: browserToolOverride,
            computerUseBackend: computerUseBackend,
            globalMemoryDirectory: globalMemoryDirectory,
            mcpToolDefinitions: mcpToolDefinitions,
            mcpToolExecutionOverride: mcpToolExecutionOverride,
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            permissionRules: permissionRules
        ).configuredRunner(from: baseRunner, modelID: modelID)
        // Attach the (opt-in) per-workspace LSP coordinator so writes get diagnostics-after-write +
        // format-on-save and the host.lsp.* tools work. The coordinator is cached per workspace so the
        // language server persists across sends; nil (feature off / remote project) leaves the runner
        // exactly as configured above.
        runner.lsp = WorkspaceLSPCoordinatorProvider.shared.coordinator(
            forWorkspace: workspaceRoot,
            isRemote: selectedProject?.isRemote == true
        )
        return runner
    }
}
