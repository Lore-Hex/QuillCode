import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceTopBarSurfaceBuilder: Sendable, Hashable {
    var topBarState: TopBarState
    var distribution: QuillCodeDistribution = .standard
    var thread: ChatThread?
    var projectName: String?
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
    var modelCatalog: [ModelInfo]
    var modelCatalogStatus: ModelCatalogStatus = .bundled
    var defaultModelID: String
    var favoriteModelIDs: [String]
    var recentThreads: [ChatThread]
    var spendPeriodThreads: [ChatThread]? = nil
    var runtimeIssue: RuntimeIssueSurface?
    var trustedRouterCredits: TrustedRouterCreditsState = .unavailable
    var hasTrustedRouterCredential: Bool = false
    var runSpendFuseUSD: Double? = nil
    var runSpendPeriodLimits: RunSpendPeriodLimits = RunSpendPeriodLimits()
    var canNavigateBack: Bool = false
    var canNavigateForward: Bool = false

    func surface() -> TopBarSurface {
        let modelCatalog = modelCatalogBuilder()
        let providerHealth = modelCatalog.providerHealthSummary()
        let worktreeStatus = thread.flatMap(Self.worktreeStatus)
        let spendStatus = thread.flatMap {
            WorkspaceTopBarSpendStatusBuilder.status(
                thread: $0,
                modelCatalog: self.modelCatalog,
                runSpendFuseUSD: runSpendFuseUSD
            )
        }
        let usageStatusLabel = thread.flatMap { thread in
            WorkspaceTokenUsageLabelBuilder.label(
                for: WorkspaceContextBannerBuilder.latestProviderUsage(for: thread)
            )
        }
        let tokenBudget = WorkspaceTokenBudgetSurfaceBuilder(
            thread: thread,
            selectedModelID: topBarState.model,
            modelCatalog: self.modelCatalog,
            quotaLimits: quotaLimitSurfaces()
        ).surface()
        let accountBalance = WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: trustedRouterCredits,
            hasCredential: hasTrustedRouterCredential
        ).surface()
        return TopBarSurface(
            appName: topBarState.appName,
            primaryTitle: thread?.title ?? QuillCodeProduct.displayName,
            subtitle: WorkspaceStatusTextBuilder.topBarSubtitle(
                projectName: projectName ?? "No project",
                thread: thread
            ),
            instructionLabel: WorkspaceStatusTextBuilder.instructionLabel(for: instructions),
            instructionSources: instructions.map(\.path),
            memoryLabel: WorkspaceStatusTextBuilder.memoryLabel(for: memories),
            memorySources: memories.map(\.relativePath),
            modelLabel: modelCatalog.modelLabel(),
            selectedModelID: topBarState.model,
            // Confidential Cowork always keeps this picker open: its authenticated catalog can add
            // eligible provider/model choices after launch. An ad hoc confidential chat in the
            // standard edition remains visibly pinned when its E2E allowlist has only one route.
            modelIsLocked: !distribution.requiresConfidentialRouting
                && thread?.runtimeContext.isConfidential == true
                && Set(modelCatalog.categories().flatMap { $0.models.map(\.id) }).count <= 1,
            modelCategories: modelCatalog.categories(),
            modelCatalogSource: modelCatalogStatus.source,
            modelCatalogStatusLabel: modelCatalogStatus.statusLabel(),
            modelCatalogStatusDetail: modelCatalogStatus.detailLabel(),
            modelProviderHealthLabel: providerHealth.label,
            modelProviderHealthDetail: providerHealth.detail,
            modeLabel: WorkspaceStatusTextBuilder.modeLabel(topBarState.mode),
            agentStatus: topBarState.agentStatus,
            liveWork: WorkspaceTopBarLiveWorkBuilder(thread: thread).surface(),
            goal: thread?.goal.map(Self.goalSurface),
            runtimeIssueLabel: runtimeIssue?.title,
            runtimeIssueSeverity: runtimeIssue?.severity,
            computerUseLabel: topBarState.computerUseStatus.message,
            showsComputerUseSetup: !topBarState.computerUseStatus.available,
            worktreeStatusLabel: worktreeStatus?.label,
            worktreeStatusDetail: worktreeStatus?.detail,
            worktreeStatusIsWarning: worktreeStatus?.isWarning ?? false,
            pullRequest: thread?.pullRequest,
            branchStatusLabel: Self.branchStatusLabel(for: topBarState.branchStatus),
            usageStatusLabel: spendStatus == nil ? usageStatusLabel : nil,
            tokenBudget: tokenBudget,
            accountBalance: accountBalance,
            spendStatusLabel: spendStatus?.label,
            spendStatusDetail: spendStatus?.detail,
            threadSpendUSD: spendStatus?.spentUSD,
            runSpendLimitUSD: runSpendFuseUSD,
            canNavigateBack: canNavigateBack,
            canNavigateForward: canNavigateForward
        )
    }

    static func branchStatusLabel(for status: GitBranchStatus?) -> String? {
        status.flatMap { value in
            let label = value.compactLabel
            return label.isEmpty ? nil : label
        }
    }

    private struct WorktreeStatus: Sendable, Hashable {
        var label: String
        var detail: String
        var isWarning: Bool
    }

    private static func goalSurface(_ goal: ThreadGoal) -> TopBarGoalSurface {
        let label: String
        let tone: TopBarGoalTone
        switch goal.status {
        case .active:
            label = "Goal"
            tone = .active
        case .blocked:
            label = "Goal blocked"
            tone = .blocked
        case .completed:
            label = "Goal complete"
            tone = .completed
        }
        var detail = "Goal: \(goal.objective). Status: \(goal.status.rawValue)."
        if let blocker = goal.blocker {
            detail += " Blocker: \(blocker)."
        }
        return TopBarGoalSurface(label: label, detail: detail, tone: tone)
    }

    private static func worktreeStatus(for thread: ChatThread) -> WorktreeStatus? {
        guard let worktree = thread.worktree else { return nil }
        if let snapshot = worktree.snapshot, worktree.canRestoreSnapshot {
            let fileLabel = "\(snapshot.fileCount) local file\(snapshot.fileCount == 1 ? "" : "s")"
            return WorktreeStatus(
                label: "Worktree saved",
                detail: "This managed worktree was removed after archive. Restore it at the captured commit with \(fileLabel) and all staged and unstaged changes.",
                isWarning: false
            )
        }
        let branch = worktree.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = worktree.location == .local
            ? "Local"
            : branch.isEmpty ? "Worktree" : "Worktree \(branch)"
        let path = worktree.path.trimmingCharacters(in: .whitespacesAndNewlines)
        var detailParts = [String]()
        if worktree.location == .local {
            detailParts.append("Runs for this task use the local checkout.")
            if !path.isEmpty {
                detailParts.append("Associated worktree: \(path).")
            }
        } else if !path.isEmpty {
            detailParts.append("Runs for this thread use \(path).")
        }
        if let base = worktree.base?.trimmingCharacters(in: .whitespacesAndNewlines), !base.isEmpty {
            detailParts.append("Base: \(base).")
        }
        let isResolvable = worktree.isResolvable
        if !isResolvable {
            let consequence = worktree.location == .local
                ? "Handoff to Worktree is unavailable until it is reopened or recreated."
                : "Runs fall back to the project root until it is reopened or recreated."
            detailParts.append("Worktree path is missing; \(consequence)")
        }
        let detail = detailParts.isEmpty ? "Runs for this thread use an isolated git worktree." : detailParts.joined(separator: " ")
        return WorktreeStatus(label: label, detail: detail, isWarning: !isResolvable)
    }

    /// Privacy filtering lives inside the builder because catalog normalization adds bundled models.
    /// Ad hoc confidential chats use the E2E policy; Confidential Cowork uses its distribution-wide
    /// Confidential-tier policy. The model-level selection and run guards remain the final authority.
    private func modelCatalogBuilder() -> WorkspaceModelCatalogSurfaceBuilder {
        WorkspaceModelCatalogSurfaceBuilder(
            catalog: modelCatalog,
            selectedModelID: topBarState.model,
            defaultModelID: defaultModelID,
            favoriteModelIDs: favoriteModelIDs,
            recentModelIDs: recentModelIDs(),
            restriction: modelCatalogRestriction
        )
    }

    private var modelCatalogRestriction: WorkspaceModelCatalogRestriction {
        if distribution.requiresConfidentialRouting {
            return .confidential
        }
        if thread?.runtimeContext.isConfidential == true {
            return .e2e
        }
        return .unrestricted
    }

    private func recentModelIDs() -> [String] {
        recentThreads
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map(\.model)
    }

    private func quotaLimitSurfaces() -> [TokenQuotaLimitSurface] {
        WorkspaceQuotaLimitSurfaceBuilder(runtimeIssue: runtimeIssue).quotaLimits()
            + WorkspaceSpendHistoryQuotaBuilder(
                threads: spendPeriodThreads ?? recentThreads,
                modelCatalog: modelCatalog,
                periodLimits: runSpendPeriodLimits
            ).quotaLimits()
    }
}
