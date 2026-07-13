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
        if let computerUseToolFeedbackAttachmentProvider {
            activeRunner.toolFeedbackAttachmentProvider = computerUseToolFeedbackAttachmentProvider
        }
        activeRunner.runSpendFusePolicy = RunSpendFusePolicy(
            fuseUSD: config.runSpendFuseUSD,
            periodLimits: config.runSpendPeriodLimits,
            periodThreads: spendPeriodThreads,
            modelCatalog: modelCatalog
        )
        if let permissionRules {
            activeRunner.safety = PermissionRuleGatedSafetyReviewer(
                base: runner.safety,
                rules: permissionRules
            )
        }
        if let modelID {
            activeRunner.llm = overridingModelIfSupported(activeRunner.llm, modelID: modelID)
        }
        return activeRunner
    }

    var baseToolDefinitions: [ToolDefinition] {
        selectedProject?.isRemote == true
            ? WorkspaceRemoteProjectToolExecutor.toolDefinitions
            : ToolRouter.definitions
    }

    var additionalToolDefinitions: [ToolDefinition] {
        var definitions = [
            ToolDefinition.planUpdate,
            ToolDefinition.handoffUpdate
        ]
        if allowsSubagents {
            definitions.append(ToolDefinition.subagentsUpdate)
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
        computerUseBackend == nil ? [] : ToolDefinition.computerUseDefinitions
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
            artifactDirectory: computerUseArtifactDirectory
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
            guard call.name == ToolDefinition.computerScreenshot.name, result.ok else { return [] }
            return Array(result.artifacts.lazy.compactMap { path in
                try? imageAttachmentStore.attachmentForManagedImage(
                    at: URL(fileURLWithPath: path),
                    displayName: "Computer Use screenshot.png"
                )
            }.prefix(1))
        }
    }

    private var remoteProjectToolExecutionOverride: AgentToolExecutionOverride? {
        WorkspaceRemoteProjectToolExecutor.executionOverride(
            project: selectedProject,
            executor: sshRemoteShellExecutor
        )
    }
}
