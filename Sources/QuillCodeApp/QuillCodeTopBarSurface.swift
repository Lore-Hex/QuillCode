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
    public var modelCategories: [ModelCategorySurface]
    public var modelCatalogStatusLabel: String
    public var modelCatalogStatusDetail: String?
    public var modeLabel: String
    public var agentStatus: String
    public var runtimeIssueLabel: String?
    public var runtimeIssueSeverity: RuntimeIssueSeverity?
    public var computerUseLabel: String
    public var showsComputerUseSetup: Bool
    /// Pre-formatted branch + ahead/behind chip (e.g. `feature/x ↑2 ↓1`), or nil
    /// when no git branch status is known. Renderers display this string as-is.
    public var branchStatusLabel: String?
    /// Pre-formatted token-usage chip (e.g. `847 ctx · ↑500 ↓347`), or nil when the model
    /// has not reported usage for this thread. Renderers display this string as-is.
    public var usageStatusLabel: String?
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
        modelCategories: [ModelCategorySurface],
        modelCatalogStatusLabel: String = ModelCatalogStatus.bundled.statusLabel(),
        modelCatalogStatusDetail: String? = ModelCatalogStatus.bundled.detailLabel(),
        modeLabel: String,
        agentStatus: String,
        runtimeIssueLabel: String? = nil,
        runtimeIssueSeverity: RuntimeIssueSeverity? = nil,
        computerUseLabel: String,
        showsComputerUseSetup: Bool,
        branchStatusLabel: String? = nil,
        usageStatusLabel: String? = nil,
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
        self.modelCategories = modelCategories
        self.modelCatalogStatusLabel = modelCatalogStatusLabel
        self.modelCatalogStatusDetail = modelCatalogStatusDetail
        self.modeLabel = modeLabel
        self.agentStatus = agentStatus
        self.runtimeIssueLabel = runtimeIssueLabel
        self.runtimeIssueSeverity = runtimeIssueSeverity
        self.computerUseLabel = computerUseLabel
        self.showsComputerUseSetup = showsComputerUseSetup
        self.branchStatusLabel = branchStatusLabel
        self.usageStatusLabel = usageStatusLabel
        self.canNavigateBack = canNavigateBack
        self.canNavigateForward = canNavigateForward
    }

    public func filteredModelCategories(matching query: String) -> [ModelCategorySurface] {
        ModelCategorySearchFilter.filter(modelCategories, matching: query)
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
