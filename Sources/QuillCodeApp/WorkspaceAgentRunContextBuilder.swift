import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodePersistence
import QuillCodeSafety
import QuillCodeTools
import QuillComputerUseKit

struct WorkspaceAgentRunContextBuilder: Sendable {
    var selectedProject: ProjectRef?
    var config: AppConfig = AppConfig()
    var modelCatalog: [ModelInfo] = []
    var spendPeriodThreads: [ChatThread] = []
    var browser: BrowserState
    var browserToolOverride: AgentToolExecutionOverride? = nil
    var computerUseBackend: (any ComputerUseBackend)?
    var imageAttachmentStore: ImageAttachmentStore? = nil
    var threadID: UUID? = nil
    var globalMemoryDirectory: URL?
    var skillResolver: SkillResolver? = nil
    var mcpToolDefinitions: [ToolDefinition]
    var mcpToolExecutionOverride: AgentToolExecutionOverride?
    var sshRemoteShellExecutor: SSHRemoteShellExecutor
    /// Per-project persisted permission rules. When present, the run's safety reviewer is wrapped
    /// so saved allow/deny/ask rules compose with (never replace) the mode + intent review.
    var permissionRules: (any PermissionRulesProviding)? = nil
    var allowsSubagents: Bool = true

    /// Configures a per-send runner. `modelID` pins THIS run's LLM client to the selected model —
    /// the thread's model — so `/model`, the top-bar picker, and the `/model` popup all take effect
    /// on the very next turn. The live runner is built once at sign-in with `config.defaultModel`;
    /// without this per-turn override a model switch would only reach the request after a Settings
    /// save or re-sign-in (the pre-existing dead-writer gap). A nil/empty `modelID` (or a mock
    /// client that can't override) leaves the client's model untouched — same model as before.
    func configuredRunner(from runner: AgentRunner, modelID: String? = nil) -> AgentRunner {
        var activeRunner = runner
        activeRunner.baseToolDefinitions = baseToolDefinitions
        activeRunner.additionalToolDefinitions = additionalToolDefinitions
        activeRunner.toolExecutionOverride = toolExecutionOverride
        activeRunner.skillResolver = skillResolver
        if let computerUseToolFeedbackAttachmentProvider {
            activeRunner.toolFeedbackAttachmentProvider = computerUseToolFeedbackAttachmentProvider
        }
        activeRunner.runSpendFusePolicy = RunSpendFusePolicy(
            fuseUSD: config.runSpendFuseUSD,
            periodLimits: config.runSpendPeriodLimits,
            periodThreads: spendPeriodThreads,
            modelCatalog: modelCatalog
        )
        // Lift the conservative library default (6) to the user-configured production budget so a
        // bare/mock runner never strangles a real task. Conditional on the runner still carrying the
        // library default: deliberately tighter budgets (delegated subagent runs, tests) survive, and
        // an explicit settings change reaches the live runner via the settings-save runtime rebuild
        // (applyRuntime), not this fill-in.
        if activeRunner.maxToolSteps == AgentRunner.defaultMaxToolSteps {
            activeRunner.maxToolSteps = config.maxToolSteps
        }
        if let permissionRules {
            activeRunner.safety = PermissionRuleGatedSafetyReviewer(
                base: runner.safety,
                rules: permissionRules
            )
        }
        if let modelID {
            activeRunner.llm = overridingModelIfSupported(activeRunner.llm, modelID: modelID)
        }
        // Proactive compaction: compact BEFORE the provider wall, sized to the ACTIVE model's real
        // context window from the catalog (85%), recomputed per send so a /model switch takes effect
        // immediately. The base runner is built reactive-only (limit 0) long before the catalog is
        // fetched; this fill-in only runs when the limit is still 0 (an explicitly configured policy
        // survives), never fabricates a compactor for runners built without one, and leaves
        // reactive-only when the catalog does not know the model's window.
        if var compaction = activeRunner.compaction,
           compaction.proactiveTokenLimit == 0,
           let limit = proactiveCompactionTokenLimit(modelID: modelID) {
            compaction.proactiveTokenLimit = limit
            activeRunner.compaction = compaction
        }
        return activeRunner
    }

    /// 85% of the active model's catalog context window, or nil when the catalog has no entry (or no
    /// window) for it — mirroring `WorkspaceTokenBudgetSurfaceBuilder`'s resolution so the compaction
    /// threshold and the top-bar token chip agree on what "the window" is.
    private func proactiveCompactionTokenLimit(modelID: String?) -> Int? {
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(modelID ?? config.defaultModel)
        let model = TrustedRouterDefaults.normalizedModelCatalog(modelCatalog).first {
            TrustedRouterDefaults.canonicalModelID($0.id) == canonicalModelID
        }
        guard let tokens = model?.capabilities.contextWindowTokens, tokens > 0 else { return nil }
        return tokens * 85 / 100
    }

    var baseToolDefinitions: [ToolDefinition] {
        guard selectedProject?.isRemote != true else {
            return WorkspaceRemoteProjectToolExecutor.toolDefinitions
        }
        guard let names = skillResolver?.availableSkillNames(), !names.isEmpty else {
            return ToolRouter.definitions
        }
        let available = names.prefix(64).map { "`\($0)`" }.joined(separator: ", ")
        return ToolRouter.definitions.map { definition in
            guard definition.name == ToolDefinition.skillLoad.name else { return definition }
            var updated = definition
            updated.description += " Available now: \(available)."
            return updated
        }
    }

    var additionalToolDefinitions: [ToolDefinition] {
        var definitions = [
            ToolDefinition.planUpdate,
            ToolDefinition.handoffUpdate
        ]
        if allowsSubagents {
            definitions.append(ToolDefinition.subagentsRun)
        }
        return definitions + [
            ToolDefinition.browserInspect,
            ToolDefinition.browserOpen,
            ToolDefinition.browserClick,
            ToolDefinition.browserType,
            ToolDefinition.browserScript
        ]
            + computerUseToolDefinitions
            + memoryToolDefinitions
            + mcpToolDefinitions
    }

    var toolExecutionOverride: AgentToolExecutionOverride? {
        WorkspaceToolExecutionOverrideCombiner.combine(
            activity: activityToolExecutionOverride,
            browser: browserToolExecutionOverride,
            computerUse: computerUseToolExecutionOverride,
            memory: WorkspaceMemoryRememberToolExecutor.executionOverride(directory: globalMemoryDirectory),
            mcp: mcpToolExecutionOverride,
            remoteProject: remoteProjectToolExecutionOverride
        )
    }

    private var computerUseToolDefinitions: [ToolDefinition] {
        guard let computerUseBackend else { return [] }
        var definitions = ToolDefinition.computerUseDefinitions
        if computerUseBackend is any WorkflowRecordingBackend {
            definitions += ToolDefinition.workflowRecordingDefinitions
        }
        return definitions
    }

    private var memoryToolDefinitions: [ToolDefinition] {
        globalMemoryDirectory == nil ? [] : [ToolDefinition.memoryRemember]
    }

    private var activityToolExecutionOverride: AgentToolExecutionOverride {
        { call, _ in
            switch call.name {
            case ToolDefinition.planUpdate.name:
                return PlanUpdateToolExecutor.execute(call)
            case ToolDefinition.handoffUpdate.name:
                return HandoffUpdateToolExecutor.execute(call)
            case ToolDefinition.subagentsUpdate.name:
                return SubagentProgressToolExecutor.execute(call)
            default:
                return nil
            }
        }
    }

    private var browserToolExecutionOverride: AgentToolExecutionOverride {
        if let browserToolOverride {
            return browserToolOverride
        }
        let snapshot = browser
        return { call, _ in
            var browser = snapshot
            var lastError: String?
            return WorkspaceBrowserToolExecutor.execute(
                call,
                workspaceRoot: nil,
                browser: &browser,
                lastError: &lastError,
                domainPolicy: config.browserDomainPolicy
            )
        }
    }

    private var computerUseToolExecutionOverride: AgentToolExecutionOverride? {
        guard let computerUseBackend else { return nil }
        let executor = ComputerUseToolExecutor(
            backend: computerUseBackend,
            appApprovalPolicy: ComputerUseAppApprovalPolicy(
                approvedBundleIdentifiers: config.computerUseApprovedBundleIdentifiers,
                approvedAppNames: config.computerUseApprovedAppNames
            ),
            artifactDirectory: computerUseArtifactDirectory,
            originThreadID: threadID?.uuidString,
            projectID: selectedProject?.id.uuidString,
            workspaceRoot: selectedProject?.isRemote == false ? selectedProject?.path : nil
        )
        return { call, _ in
            await executor.execute(call)
        }
    }

    private var computerUseArtifactDirectory: URL {
        guard let imageAttachmentStore, let threadID else {
            return ComputerUseToolExecutor.defaultArtifactDirectory
        }
        return imageAttachmentStore.directory
            .appendingPathComponent(threadID.uuidString, isDirectory: true)
            .appendingPathComponent("computer-use", isDirectory: true)
    }

    private var computerUseToolFeedbackAttachmentProvider: AgentToolFeedbackAttachmentProvider? {
        guard computerUseBackend != nil,
              threadID != nil,
              let imageAttachmentStore
        else { return nil }
        return { call, result in
            guard result.ok else { return [] }
            let limit: Int
            let displayName: (Int) -> String
            switch call.name {
            case ToolDefinition.computerScreenshot.name:
                limit = 1
                displayName = { _ in "Computer Use screenshot.png" }
            case ToolDefinition.workflowRecordStop.name:
                limit = 4
                displayName = { "Workflow recording \($0 + 1).png" }
            default:
                return []
            }
            return Array(result.artifacts.lazy.enumerated().compactMap { index, path in
                try? imageAttachmentStore.attachmentForManagedImage(
                    at: URL(fileURLWithPath: path),
                    displayName: displayName(index)
                )
            }.prefix(limit))
        }
    }

    private var remoteProjectToolExecutionOverride: AgentToolExecutionOverride? {
        WorkspaceRemoteProjectToolExecutor.executionOverride(
            project: selectedProject,
            executor: sshRemoteShellExecutor
        )
    }
}
