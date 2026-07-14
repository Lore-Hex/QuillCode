import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
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
    private let imageAttachmentStore: ImageAttachmentStore?
    private let globalMemoryDirectory: URL?
    private let pluginDataBaseDirectory: URL?
    private let skillResolver: SkillResolver
    private let mcpToolDefinitions: [ToolDefinition]
    private let mcpToolExecutionOverride: AgentToolExecutionOverride?
    private let sshRemoteShellExecutor: SSHRemoteShellExecutor
    private let permissionRules: (any PermissionRulesProviding)?
    private let workspaceRoot: URL
    private let subagentThreadStore: SubagentThreadStore?
    private let subagentApprovalPayloadStore: SubagentApprovalPayloadStore?
    private let subagentSchedulerOverride: WorkspaceSubagentScheduler?
    private let subagentRunRecordSink: WorkspaceSubagentRunRecordSink?

    init(
        baseRunner: AgentRunner,
        selectedProject: ProjectRef?,
        config: AppConfig,
        modelCatalog: [ModelInfo] = [],
        spendPeriodThreads: [ChatThread] = [],
        browser: BrowserState,
        browserToolOverride: AgentToolExecutionOverride?,
        computerUseBackend: (any ComputerUseBackend)?,
        imageAttachmentStore: ImageAttachmentStore? = nil,
        globalMemoryDirectory: URL?,
        pluginDataBaseDirectory: URL? = nil,
        mcpToolDefinitions: [ToolDefinition],
        mcpToolExecutionOverride: AgentToolExecutionOverride?,
        sshRemoteShellExecutor: SSHRemoteShellExecutor,
        permissionRules: (any PermissionRulesProviding)? = nil,
        subagentThreadStore: SubagentThreadStore? = nil,
        subagentApprovalPayloadStore: SubagentApprovalPayloadStore? = nil,
        subagentSchedulerOverride: WorkspaceSubagentScheduler? = nil,
        subagentRunRecordSink: WorkspaceSubagentRunRecordSink? = nil,
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
        self.imageAttachmentStore = imageAttachmentStore
        self.globalMemoryDirectory = globalMemoryDirectory
        self.pluginDataBaseDirectory = pluginDataBaseDirectory
        self.skillResolver = WorkspacePluginSkillResolver.make(
            workspaceRoot: workspaceRoot,
            manifests: selectedProject?.extensionManifests ?? []
        )
        self.mcpToolDefinitions = mcpToolDefinitions
        self.mcpToolExecutionOverride = mcpToolExecutionOverride
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
        self.permissionRules = permissionRules
        self.subagentThreadStore = subagentThreadStore
        self.subagentApprovalPayloadStore = subagentApprovalPayloadStore
        self.subagentSchedulerOverride = subagentSchedulerOverride
        self.subagentRunRecordSink = subagentRunRecordSink
        self.workspaceRoot = workspaceRoot
    }

    func makeSession(
        prompt: String,
        thread: ChatThread,
        recordsUserMessage: Bool = true,
        allowsSubagents: Bool? = nil
    ) -> WorkspaceAgentSendSession {
        let permitsSubagents = allowsSubagents ?? !thread.runtimeContext.isEphemeral
        return WorkspaceAgentSendSession(
            prompt: prompt,
            thread: thread,
            // Pin this run to the THREAD's selected model so a `/model` switch (popup, typed, or
            // top-bar picker) takes effect on the next turn without a Settings save/re-sign-in, and
            // so each thread runs on its own model.
            runner: configuredRunner(
                modelID: thread.model,
                threadID: thread.id,
                allowsSubagents: permitsSubagents
            ),
            workspaceRoot: workspaceRoot,
            recordsUserMessage: recordsUserMessage,
            runHooks: selectedProject?.runHooks ?? [],
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    func resumeApproved(
        _ pendingApproval: AgentPendingApproval,
        prompt: String,
        thread: ChatThread,
        onProgress: AgentRunProgressHandler? = nil,
        allowsSubagents: Bool? = nil
    ) async throws -> WorkspaceAgentSendSessionResult {
        try await makeSession(
            prompt: prompt,
            thread: thread,
            recordsUserMessage: false,
            allowsSubagents: allowsSubagents
        ).resumeApproved(pendingApproval, onProgress: onProgress)
    }

    /// Builds the per-send runner, retargeting its LLM client at `modelID` (the thread's model).
    /// Internal (not private) so tests can assert the run path actually points at the selected
    /// model — the run-path is the load-bearing part of `/model`, not the persisted field alone.
    func configuredRunner(
        modelID: String?,
        threadID: UUID? = nil,
        allowsSubagents: Bool = true
    ) -> AgentRunner {
        var runner = WorkspaceAgentRunContextBuilder(
            selectedProject: selectedProject,
            config: config,
            modelCatalog: modelCatalog,
            spendPeriodThreads: spendPeriodThreads,
            browser: browser,
            browserToolOverride: browserToolOverride,
            computerUseBackend: computerUseBackend,
            imageAttachmentStore: imageAttachmentStore,
            threadID: threadID,
            globalMemoryDirectory: globalMemoryDirectory,
            skillResolver: skillResolver,
            mcpToolDefinitions: mcpToolDefinitions,
            mcpToolExecutionOverride: mcpToolExecutionOverride,
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            permissionRules: permissionRules,
            allowsSubagents: allowsSubagents
        ).configuredRunner(from: baseRunner, modelID: modelID)
        // Attach the (opt-in) per-workspace LSP coordinator so writes get diagnostics-after-write +
        // format-on-save and the host.lsp.* tools work. The coordinator is cached per workspace so the
        // language server persists across sends; nil (feature off / remote project) leaves the runner
        // exactly as configured above.
        runner.lsp = WorkspaceLSPCoordinatorProvider.shared.coordinator(
            forWorkspace: workspaceRoot,
            isRemote: selectedProject?.isRemote == true
        )
        if allowsSubagents {
            runner.threadToolExecutionOverride = WorkspaceSubagentRunToolExecutor(
                sessionFactory: self,
                threadStore: subagentThreadStore,
                approvalPayloadStore: subagentApprovalPayloadStore,
                schedulerOverride: subagentSchedulerOverride,
                recordSink: subagentRunRecordSink
            ).executionOverride
        } else {
            runner.threadToolExecutionOverride = nil
        }
        let pluginToolHooks = ProjectPluginToolHookExecutor(
            hooks: selectedProject?.pluginHooks ?? [],
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
        if let preToolUseHook = pluginToolHooks.preToolUseHook {
            runner.preToolUseHook = preToolUseHook
        }
        if let postToolUseHook = pluginToolHooks.postToolUseHook {
            runner.postToolUseHook = postToolUseHook
        }
        if let permissionRequestHook = pluginToolHooks.permissionRequestHook {
            runner.permissionRequestHook = permissionRequestHook
        }
        let pluginCompactionHooks = ProjectPluginCompactionHookExecutor(
            hooks: selectedProject?.pluginHooks ?? [],
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
        if let preCompactHook = pluginCompactionHooks.preCompactHook {
            runner.preCompactHook = preCompactHook
        }
        if let postCompactHook = pluginCompactionHooks.postCompactHook {
            runner.postCompactHook = postCompactHook
        }
        return runner
    }
}
