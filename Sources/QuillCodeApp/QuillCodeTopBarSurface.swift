import Foundation
import QuillCodeCore

public struct TopBarSurface: Codable, Sendable, Hashable {
    public var appName: String
    public var primaryTitle: String
    public var subtitle: String
    public var instructionLabel: String
    public var instructionSources: [String]
    public var memoryLabel: String
    public var memorySources: [String]
    public var modelLabel: String
    public var selectedModelID: String
    /// True when the selected thread's model is pinned for its lifetime (incognito chats pin the
    /// E2E-encrypted route). Renderers show a locked, non-interactive model chip instead of a picker.
    public var modelIsLocked: Bool
    public var modelCategories: [ModelCategorySurface]
    public var modelCatalogSource: ModelCatalogSource?
    public var modelCatalogStatusLabel: String
    public var modelCatalogStatusDetail: String?
    public var modelProviderHealthLabel: String?
    public var modelProviderHealthDetail: String?
    public var modeLabel: String
    public var agentStatus: String
    /// Compact summary of currently queued/running/review-gated work for the selected thread.
    public var liveWork: TopBarLiveWorkSurface?
    /// Compact durable-goal status for the selected thread. The full objective stays in detail text
    /// so the one-line top bar remains quiet even for long goals.
    public var goal: TopBarGoalSurface?
    public var runtimeIssueLabel: String?
    public var runtimeIssueSeverity: RuntimeIssueSeverity?
    public var computerUseLabel: String
    public var showsComputerUseSetup: Bool
    /// Worktree isolation chip for the selected thread, e.g. `Worktree feature/ui`.
    /// Present when the thread is bound to a worktree, even if the directory has gone missing.
    public var worktreeStatusLabel: String?
    /// Tooltip/accessibility detail for the worktree chip, including path and fallback state.
    public var worktreeStatusDetail: String?
    /// True when the bound worktree path cannot be resolved and runs have fallen back to project root.
    public var worktreeStatusIsWarning: Bool
    /// Durable pull-request identity and lifecycle state for the selected task.
    public var pullRequest: PullRequestLink?
    /// Pre-formatted branch + ahead/behind chip (e.g. `feature/x ↑2 ↓1`), or nil
    /// when no git branch status is known. Renderers display this string as-is.
    public var branchStatusLabel: String?
    /// Pre-formatted token-usage chip (e.g. `847 ctx · ↑500 ↓347`), or nil when the model
    /// has not reported usage for this thread. Renderers display this string as-is.
    public var usageStatusLabel: String?
    /// Prominent context-window budget meter. Uses provider-reported usage when available and
    /// falls back to a local estimate so the user can see used/limit/left before the first reply.
    public var tokenBudget: TokenBudgetSurface?
    /// Current provider account credit balance. This is intentionally separate from context-window
    /// usage and local spend limits because it comes directly from TrustedRouter's account endpoint.
    public var accountBalance: ProviderAccountBalanceSurface?
    /// Pre-formatted spend chip (e.g. `Spend $0.0050 / $1.00`), or nil when the thread has no
    /// priced provider usage. When present, renderers prefer this over the raw token-usage chip.
    public var spendStatusLabel: String?
    /// Tooltip/accessibility detail for `spendStatusLabel`, including unpriced-call and token context.
    public var spendStatusDetail: String?
    public var canNavigateBack: Bool
    public var canNavigateForward: Bool

    public init(
        appName: String,
        primaryTitle: String,
        subtitle: String,
        instructionLabel: String,
        instructionSources: [String],
        memoryLabel: String,
        memorySources: [String],
        modelLabel: String,
        selectedModelID: String,
        modelIsLocked: Bool = false,
        modelCategories: [ModelCategorySurface],
        modelCatalogSource: ModelCatalogSource? = .bundled,
        modelCatalogStatusLabel: String = ModelCatalogStatus.bundled.statusLabel(),
        modelCatalogStatusDetail: String? = ModelCatalogStatus.bundled.detailLabel(),
        modelProviderHealthLabel: String? = nil,
        modelProviderHealthDetail: String? = nil,
        modeLabel: String,
        agentStatus: String,
        liveWork: TopBarLiveWorkSurface? = nil,
        goal: TopBarGoalSurface? = nil,
        runtimeIssueLabel: String? = nil,
        runtimeIssueSeverity: RuntimeIssueSeverity? = nil,
        computerUseLabel: String,
        showsComputerUseSetup: Bool,
        worktreeStatusLabel: String? = nil,
        worktreeStatusDetail: String? = nil,
        worktreeStatusIsWarning: Bool = false,
        pullRequest: PullRequestLink? = nil,
        branchStatusLabel: String? = nil,
        usageStatusLabel: String? = nil,
        tokenBudget: TokenBudgetSurface? = nil,
        accountBalance: ProviderAccountBalanceSurface? = nil,
        spendStatusLabel: String? = nil,
        spendStatusDetail: String? = nil,
        canNavigateBack: Bool = false,
        canNavigateForward: Bool = false
    ) {
        self.appName = appName
        self.primaryTitle = primaryTitle
        self.subtitle = subtitle
        self.instructionLabel = instructionLabel
        self.instructionSources = instructionSources
        self.memoryLabel = memoryLabel
        self.memorySources = memorySources
        self.modelLabel = modelLabel
        self.selectedModelID = selectedModelID
        self.modelIsLocked = modelIsLocked
        self.modelCategories = modelCategories
        self.modelCatalogSource = modelCatalogSource
        self.modelCatalogStatusLabel = modelCatalogStatusLabel
        self.modelCatalogStatusDetail = modelCatalogStatusDetail
        self.modelProviderHealthLabel = modelProviderHealthLabel
        self.modelProviderHealthDetail = modelProviderHealthDetail
        self.modeLabel = modeLabel
        self.agentStatus = agentStatus
        self.liveWork = liveWork
        self.goal = goal
        self.runtimeIssueLabel = runtimeIssueLabel
        self.runtimeIssueSeverity = runtimeIssueSeverity
        self.computerUseLabel = computerUseLabel
        self.showsComputerUseSetup = showsComputerUseSetup
        self.worktreeStatusLabel = worktreeStatusLabel
        self.worktreeStatusDetail = worktreeStatusDetail
        self.worktreeStatusIsWarning = worktreeStatusIsWarning
        self.pullRequest = pullRequest
        self.branchStatusLabel = branchStatusLabel
        self.usageStatusLabel = usageStatusLabel
        self.tokenBudget = tokenBudget
        self.accountBalance = accountBalance
        self.spendStatusLabel = spendStatusLabel
        self.spendStatusDetail = spendStatusDetail
        self.canNavigateBack = canNavigateBack
        self.canNavigateForward = canNavigateForward
    }

    public func filteredModelCategories(matching query: String) -> [ModelCategorySurface] {
        ModelCategorySearchFilter.filter(modelCategories, matching: query)
    }

    public func filteredModelScopeSummary(matching query: String) -> String? {
        ModelCategorySearchFilter.scopeSummary(for: filteredModelCategories(matching: query))
    }
}

public enum TopBarGoalTone: String, Codable, Sendable, Hashable {
    case active
    case blocked
    case completed
}

public struct TopBarGoalSurface: Codable, Sendable, Hashable {
    public var label: String
    public var detail: String
    public var tone: TopBarGoalTone

    public init(label: String, detail: String, tone: TopBarGoalTone) {
        self.label = label
        self.detail = detail
        self.tone = tone
    }
}

public enum TopBarLiveWorkTone: String, Codable, Sendable, Hashable {
    case running
    case review
}

public struct TopBarLiveWorkSurface: Codable, Sendable, Hashable {
    public var label: String
    public var detail: String
    public var tone: TopBarLiveWorkTone

    public init(label: String, detail: String, tone: TopBarLiveWorkTone) {
        self.label = label
        self.detail = detail
        self.tone = tone
    }
}

public struct TokenBudgetSurface: Codable, Sendable, Hashable {
    public var usedTokens: Int
    public var limitTokens: Int
    public var remainingTokens: Int
    public var usedPercent: Int
    public var progressPercent: Int
    public var primaryLabel: String
    public var secondaryLabel: String
    public var detailLabel: String
    public var sourceLabel: String
    /// Optional account/provider quota periods, such as day/week/month. The context-window budget
    /// is always shown above; these only render when real quota data is supplied.
    public var quotaLimits: [TokenQuotaLimitSurface]?

    public init(
        usedTokens: Int,
        limitTokens: Int,
        remainingTokens: Int,
        usedPercent: Int,
        progressPercent: Int,
        primaryLabel: String,
        secondaryLabel: String,
        detailLabel: String,
        sourceLabel: String,
        quotaLimits: [TokenQuotaLimitSurface] = []
    ) {
        self.usedTokens = max(0, usedTokens)
        self.limitTokens = max(1, limitTokens)
        self.remainingTokens = max(0, remainingTokens)
        self.usedPercent = max(0, usedPercent)
        self.progressPercent = min(100, max(0, progressPercent))
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.detailLabel = detailLabel
        self.sourceLabel = sourceLabel
        self.quotaLimits = quotaLimits.isEmpty ? nil : quotaLimits
    }

    public var visibleQuotaLimits: [TokenQuotaLimitSurface] {
        quotaLimits ?? []
    }

    public var quotaSummaryLabel: String? {
        let summary = visibleQuotaLimits.map(\.compactLabel).joined(separator: " · ")
        return summary.isEmpty ? nil : summary
    }

    public var accessibilityLabel: String {
        var parts = [detailLabel]
        if let quotaSummaryLabel {
            parts.append("Quota limits: \(quotaSummaryLabel)")
        }
        return parts.joined(separator: " · ")
    }
}

public struct TokenQuotaLimitSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { periodLabel }
    public var periodLabel: String
    public var usageLabel: String
    public var detailLabel: String

    public init(periodLabel: String, usageLabel: String, detailLabel: String) {
        self.periodLabel = periodLabel
        self.usageLabel = usageLabel
        self.detailLabel = detailLabel
    }

    public var compactLabel: String {
        "\(periodLabel) \(usageLabel)"
    }
}

public struct ModelCategorySurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { category }
    public var category: String
    public var models: [ModelOptionSurface]

    public init(category: String, models: [ModelOptionSurface]) {
        self.category = category
        self.models = models
    }

    public var modelCountLabel: String {
        let noun = models.count == 1 ? "model" : "models"
        return "\(models.count) \(noun)"
    }

    public var sectionTitle: String {
        "\(category) · \(modelCountLabel)"
    }

    public var providerCountLabel: String {
        let count = uniqueProviders.count
        let noun = count == 1 ? "provider" : "providers"
        return "\(count) \(noun)"
    }

    public var providerSummaryLabel: String {
        let providers = uniqueProviders
        guard !providers.isEmpty else {
            return "No providers"
        }

        let visibleProviders = providers.prefix(3)
        let overflowCount = providers.count - visibleProviders.count
        let visibleSummary = visibleProviders.joined(separator: ", ")
        return overflowCount > 0 ? "\(visibleSummary) +\(overflowCount) more" : visibleSummary
    }

    public var accessibilityLabel: String {
        "\(category), \(modelCountLabel), \(providerCountLabel): \(providerSummaryLabel)"
    }

    private var uniqueProviders: [String] {
        var seen = Set<String>()
        return models.compactMap { option in
            let provider = option.provider.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !provider.isEmpty else {
                return nil
            }

            let key = provider.lowercased()
            guard seen.insert(key).inserted else {
                return nil
            }
            return provider
        }
    }
}

public struct ModelMetadataRowSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { label }
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ModelOptionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var category: String
    public var isSelected: Bool
    public var isFavorite: Bool
    public var badges: [String]
    public var capabilities: ModelCapabilities
    public var metadataSummary: String
    public var metadataDetails: [String]
    public var detailTitle: String
    public var capabilitySummary: String
    public var metadataRows: [ModelMetadataRowSurface]
    public var modelInfo: ModelInfo {
        ModelInfo(id: id, provider: provider, displayName: displayName, category: category, capabilities: capabilities)
    }

    public init(model: ModelInfo, selectedModelID: String, isFavorite: Bool = false, badges: [String] = []) {
        self.id = model.id
        self.provider = model.provider
        self.displayName = model.displayName
        self.category = model.category
        self.isSelected = model.id == selectedModelID
        self.isFavorite = isFavorite
        self.badges = badges
        self.capabilities = model.capabilities
        self.metadataSummary = Self.metadataSummary(
            modelID: model.id,
            category: model.category,
            capabilities: model.capabilities
        )
        self.detailTitle = Self.detailTitle(modelID: model.id, provider: model.provider, displayName: model.displayName)
        self.capabilitySummary = Self.capabilitySummary(
            modelID: model.id,
            category: model.category,
            badges: badges,
            capabilities: model.capabilities
        )
        self.metadataRows = Self.metadataRows(
            provider: model.provider,
            modelID: model.id,
            category: model.category,
            capabilities: model.capabilities,
            isSelected: model.id == selectedModelID,
            isFavorite: isFavorite,
            badges: badges
        )
        self.metadataDetails = Self.metadataDetails(
            provider: model.provider,
            modelID: model.id,
            category: model.category,
            capabilities: model.capabilities,
            isSelected: model.id == selectedModelID,
            isFavorite: isFavorite,
            badges: badges
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case displayName
        case category
        case isSelected
        case isFavorite
        case badges
        case capabilities
        case metadataSummary
        case metadataDetails
        case detailTitle
        case capabilitySummary
        case metadataRows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = TrustedRouterDefaults.canonicalModelID(try container.decode(String.self, forKey: .id))
        self.provider = TrustedRouterDefaults.canonicalProvider(try container.decode(String.self, forKey: .provider))
        self.displayName = try container.decode(String.self, forKey: .displayName)
        self.category = try container.decode(String.self, forKey: .category)
        self.isSelected = try container.decode(Bool.self, forKey: .isSelected)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.badges = try container.decodeIfPresent([String].self, forKey: .badges) ?? []
        self.capabilities = try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities) ?? .init()
        self.metadataSummary = try container.decodeIfPresent(String.self, forKey: .metadataSummary)
            ?? Self.metadataSummary(modelID: id, category: category, capabilities: capabilities)
        self.detailTitle = try container.decodeIfPresent(String.self, forKey: .detailTitle)
            ?? Self.detailTitle(modelID: id, provider: provider, displayName: displayName)
        self.capabilitySummary = try container.decodeIfPresent(String.self, forKey: .capabilitySummary)
            ?? Self.capabilitySummary(modelID: id, category: category, badges: badges, capabilities: capabilities)
        self.metadataRows = try container.decodeIfPresent([ModelMetadataRowSurface].self, forKey: .metadataRows)
            ?? Self.metadataRows(
                provider: provider,
                modelID: id,
                category: category,
                capabilities: capabilities,
                isSelected: isSelected,
                isFavorite: isFavorite,
                badges: badges
            )
        self.metadataDetails = try container.decodeIfPresent([String].self, forKey: .metadataDetails)
            ?? Self.metadataDetails(
                provider: provider,
                modelID: id,
                category: category,
                capabilities: capabilities,
                isSelected: isSelected,
                isFavorite: isFavorite,
                badges: badges
            )
    }

}
