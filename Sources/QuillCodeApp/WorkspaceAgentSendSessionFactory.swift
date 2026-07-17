import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeReview
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
    private let mcpStreamingToolExecutionOverride: AgentStreamingToolExecutionOverride?
    private let sshRemoteShellExecutor: SSHRemoteShellExecutor
    private let sshRemoteAppServer: (any SSHRemoteAppServerExecuting)?
    private let permissionRules: (any PermissionRulesProviding)?
    private let workspaceRoot: URL
    private let subagentThreadStore: SubagentThreadStore?
    private let subagentApprovalPayloadStore: SubagentApprovalPayloadStore?
    private let subagentSchedulerOverride: WorkspaceSubagentScheduler?
    private let subagentRunRecordSink: WorkspaceSubagentRunRecordSink?
    private let sessionStartHookCoordinator: WorkspaceSessionStartHookCoordinator
    private let hooks: [ProjectPluginHook]
    private let runHooks: [ProjectRunHook]

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
        mcpStreamingToolExecutionOverride: AgentStreamingToolExecutionOverride? = nil,
        sshRemoteShellExecutor: SSHRemoteShellExecutor,
        sshRemoteAppServer: (any SSHRemoteAppServerExecuting)? = nil,
        permissionRules: (any PermissionRulesProviding)? = nil,
        subagentThreadStore: SubagentThreadStore? = nil,
        subagentApprovalPayloadStore: SubagentApprovalPayloadStore? = nil,
        subagentSchedulerOverride: WorkspaceSubagentScheduler? = nil,
        subagentRunRecordSink: WorkspaceSubagentRunRecordSink? = nil,
        sessionStartHookCoordinator: WorkspaceSessionStartHookCoordinator = WorkspaceSessionStartHookCoordinator(),
        hooks: [ProjectPluginHook]? = nil,
        runHooks: [ProjectRunHook]? = nil,
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
            manifests: selectedProject?.extensionManifests ?? [],
            configuration: config.skillConfiguration
        )
        self.mcpToolDefinitions = mcpToolDefinitions
        self.mcpToolExecutionOverride = mcpToolExecutionOverride
        self.mcpStreamingToolExecutionOverride = mcpStreamingToolExecutionOverride
        self.sshRemoteShellExecutor = sshRemoteShellExecutor
        self.sshRemoteAppServer = sshRemoteAppServer
        self.permissionRules = permissionRules
        self.subagentThreadStore = subagentThreadStore
        self.subagentApprovalPayloadStore = subagentApprovalPayloadStore
        self.subagentSchedulerOverride = subagentSchedulerOverride
        self.subagentRunRecordSink = subagentRunRecordSink
        self.sessionStartHookCoordinator = sessionStartHookCoordinator
        self.hooks = hooks ?? selectedProject?.pluginHooks ?? []
        self.runHooks = runHooks ?? selectedProject?.runHooks ?? []
        self.workspaceRoot = workspaceRoot
    }

    func makeSession(
        prompt: String,
        thread: ChatThread,
        recordsUserMessage: Bool = true,
        allowsSubagents: Bool? = nil,
        lifecycle: WorkspaceAgentSessionLifecycle? = nil
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
                allowsSubagents: permitsSubagents,
                threadIsConfidential: thread.runtimeContext.isConfidential
            ),
            workspaceRoot: workspaceRoot,
            recordsUserMessage: recordsUserMessage,
            // Run hooks receive the raw prompt / last assistant message on stdin and execute
            // arbitrary user-configured shell — an automatic hook could persist confidential content
            // despite the "never saved" contract. Confidential sessions run without them.
            runHooks: thread.runtimeContext.isConfidential ? [] : runHooks,
            // A SessionStart plugin hook appends its stdout / additionalContext as a system message —
            // durable workspace context injected into the private conversation, the exact thing the
            // confidential guards keep out. Run with no lifecycle hooks for confidential (an empty executor
            // makes prepareLifecycle's report a no-op even though the .primary case still fires).
            pluginLifecycleHooks: thread.runtimeContext.isConfidential ? emptyPluginLifecycleHooks : pluginLifecycleHooks,
            lifecycle: lifecycle ?? .primary(sessionStartHookCoordinator),
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    func makeSubagentSession(
        prompt: String,
        thread: ChatThread,
        parentThread: ChatThread,
        job: WorkspaceSubagentJob,
        recordsUserMessage: Bool = true,
        runsStartHook: Bool
    ) -> WorkspaceAgentSendSession {
        makeSession(
            prompt: prompt,
            thread: thread,
            recordsUserMessage: recordsUserMessage,
            allowsSubagents: false,
            lifecycle: .subagent(
                parentThread: parentThread,
                job: job,
                threadStore: subagentThreadStore,
                runsStartHook: runsStartHook
            )
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
        allowsSubagents: Bool = true,
        threadIsConfidential: Bool = false
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
            mcpStreamingToolExecutionOverride: mcpStreamingToolExecutionOverride,
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            sshRemoteAppServer: sshRemoteAppServer,
            permissionRules: permissionRules,
            allowsSubagents: allowsSubagents,
            threadIsConfidential: threadIsConfidential
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
        // Plugin tool/compaction hooks execute user-configured shell with tool inputs/results (and
        // compaction summaries) on stdin — external processes that commonly log what they receive.
        // Confidential runs skip them entirely, like run hooks: "never saved" must hold against every
        // configured egress, not just QuillCode-owned files.
        if !threadIsConfidential {
            let pluginToolHooks = ProjectPluginToolHookExecutor(
                hooks: hooks,
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
                hooks: hooks,
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
        }
        return runner
    }

    /// Builds the dedicated code-review runner. This is a capability boundary, not merely a prompt:
    /// the reviewer receives only file/Git read tools plus the typed report sink. Even a malformed or
    /// adversarial model action cannot fall through to shell, writes, browser, plugins, MCP, memories,
    /// Computer Use, LSP mutation, subagents, or project hooks.
    func configuredCodeReviewRunner(
        modelID: String,
        threadID: UUID,
        reportCollector: WorkspaceCodeReviewReportCollector,
        threadIsConfidential: Bool = false
    ) -> AgentRunner {
        // A code review started from a confidential chat must honor the same E2E pin as the chat
        // itself: force the reviewer onto the E2E route (ignoring the configured review model) and
        // carry the confidential flag so its safety/compaction auxiliaries stay model-free too.
        let reviewer = configuredRunner(
            modelID: threadIsConfidential ? TrustedRouterDefaults.e2eModel : modelID,
            threadID: threadID,
            allowsSubagents: false,
            threadIsConfidential: threadIsConfidential
        )
        return WorkspaceCodeReviewRunner.configure(
            reviewer,
            reportCollector: reportCollector
        )
    }

    private var pluginLifecycleHooks: ProjectPluginLifecycleHookExecutor {
        ProjectPluginLifecycleHookExecutor(
            hooks: hooks,
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }

    /// A lifecycle-hook executor with no hooks — its SessionStart run produces an empty, context-free
    /// report. Used for confidential sends so no plugin can inject durable workspace context.
    private var emptyPluginLifecycleHooks: ProjectPluginLifecycleHookExecutor {
        ProjectPluginLifecycleHookExecutor(
            hooks: [],
            pluginDataBaseDirectory: pluginDataBaseDirectory,
            selectedProject: selectedProject,
            sshRemoteShellExecutor: sshRemoteShellExecutor
        )
    }
}
