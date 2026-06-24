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
    public var modeLabel: String
    public var agentStatus: String
    public var runtimeIssueLabel: String?
    public var runtimeIssueSeverity: RuntimeIssueSeverity?
    public var computerUseLabel: String
    public var showsComputerUseSetup: Bool

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
        modeLabel: String,
        agentStatus: String,
        runtimeIssueLabel: String? = nil,
        runtimeIssueSeverity: RuntimeIssueSeverity? = nil,
        computerUseLabel: String,
        showsComputerUseSetup: Bool
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
        self.modeLabel = modeLabel
        self.agentStatus = agentStatus
        self.runtimeIssueLabel = runtimeIssueLabel
        self.runtimeIssueSeverity = runtimeIssueSeverity
        self.computerUseLabel = computerUseLabel
        self.showsComputerUseSetup = showsComputerUseSetup
    }

    public func filteredModelCategories(matching query: String) -> [ModelCategorySurface] {
        let normalizedTerms = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard !normalizedTerms.isEmpty else {
            return modelCategories
        }

        let includesFavoriteTerm = normalizedTerms.contains("favorite") || normalizedTerms.contains("favorites")
        let includesRecentTerm = normalizedTerms.contains("recent")
        return modelCategories.compactMap { category in
            if includesFavoriteTerm && category.category != "Favorites" {
                return nil
            }
            if includesRecentTerm && category.category != "Recent" {
                return nil
            }
            if category.category == "Favorites" && !includesFavoriteTerm {
                return nil
            }
            if category.category == "Recent" && !includesRecentTerm {
                return nil
            }
            let models = category.models.filter { option in
                let haystack = [
                    category.category,
                    option.id,
                    option.provider,
                    option.displayName,
                    option.category,
                    option.detailTitle,
                    option.metadataSummary,
                    option.metadataDetails.joined(separator: " "),
                    option.metadataRows.map { row in
                        row.label == "State" ? "state \(row.value)" : row.value
                    }.joined(separator: " "),
                    option.badges.joined(separator: " ")
                ].joined(separator: " ").lowercased()
                return normalizedTerms.allSatisfy { haystack.contains($0) }
            }
            guard !models.isEmpty else { return nil }
            return ModelCategorySurface(category: category.category, models: models)
        }
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
    public var metadataSummary: String
    public var metadataDetails: [String]
    public var detailTitle: String
    public var capabilitySummary: String
    public var metadataRows: [ModelMetadataRowSurface]
    public var modelInfo: ModelInfo {
        ModelInfo(id: id, provider: provider, displayName: displayName, category: category)
    }

    public init(model: ModelInfo, selectedModelID: String, isFavorite: Bool = false, badges: [String] = []) {
        self.id = model.id
        self.provider = model.provider
        self.displayName = model.displayName
        self.category = model.category
        self.isSelected = model.id == selectedModelID
        self.isFavorite = isFavorite
        self.badges = badges
        self.metadataSummary = Self.metadataSummary(modelID: model.id, category: model.category)
        self.detailTitle = Self.detailTitle(modelID: model.id, provider: model.provider, displayName: model.displayName)
        self.capabilitySummary = Self.capabilitySummary(modelID: model.id, category: model.category, badges: badges)
        self.metadataRows = Self.metadataRows(
            provider: model.provider,
            modelID: model.id,
            category: model.category,
            isSelected: model.id == selectedModelID,
            isFavorite: isFavorite,
            badges: badges
        )
        self.metadataDetails = Self.metadataDetails(
            provider: model.provider,
            modelID: model.id,
            category: model.category,
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
        self.metadataSummary = try container.decodeIfPresent(String.self, forKey: .metadataSummary)
            ?? Self.metadataSummary(modelID: id, category: category)
        self.detailTitle = try container.decodeIfPresent(String.self, forKey: .detailTitle)
            ?? Self.detailTitle(modelID: id, provider: provider, displayName: displayName)
        self.capabilitySummary = try container.decodeIfPresent(String.self, forKey: .capabilitySummary)
            ?? Self.capabilitySummary(modelID: id, category: category, badges: badges)
        self.metadataRows = try container.decodeIfPresent([ModelMetadataRowSurface].self, forKey: .metadataRows)
            ?? Self.metadataRows(
                provider: provider,
                modelID: id,
                category: category,
                isSelected: isSelected,
                isFavorite: isFavorite,
                badges: badges
            )
        self.metadataDetails = try container.decodeIfPresent([String].self, forKey: .metadataDetails)
            ?? Self.metadataDetails(
                provider: provider,
                modelID: id,
                category: category,
                isSelected: isSelected,
                isFavorite: isFavorite,
                badges: badges
            )
    }

    private static func metadataSummary(modelID: String, category: String) -> String {
        let canonicalModelID = TrustedRouterDefaults.canonicalModelID(modelID)
        if canonicalModelID == TrustedRouterDefaults.defaultModel {
            return "Fast everyday agent"
        }
        if canonicalModelID == TrustedRouterDefaults.synthModel {
            return "Deeper planning and review"
        }
        if category == TrustedRouterDefaults.safetyCategory {
            return "Auto safety reviewer"
        }
        return "\(category) model"
    }

    private static func detailTitle(modelID: String, provider: String, displayName: String) -> String {
        if let recommendedName = TrustedRouterDefaults.recommendedDisplayNames[TrustedRouterDefaults.canonicalModelID(modelID)] {
            return recommendedName
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            return trimmedDisplayName
        }
        return modelID
    }

    private static func capabilitySummary(modelID: String, category: String, badges: [String]) -> String {
        if modelID == TrustedRouterDefaults.defaultModel {
            return "\(TrustedRouterDefaults.fastModelDisplayName) is the fast default for coding, shell, and file-editing turns."
        }
        if modelID == TrustedRouterDefaults.synthModel {
            return "\(TrustedRouterDefaults.synthModelDisplayName) is the balanced model for deeper coding and review turns."
        }
        if badges.contains("Recommended") {
            return "Recommended model profile available through TrustedRouter."
        }
        if category == "Safety" {
            return "Lightweight reviewer model for Auto safety decisions."
        }
        return "\(category) model available through TrustedRouter."
    }

    private static func metadataRows(
        provider: String,
        modelID: String,
        category: String,
        isSelected: Bool,
        isFavorite: Bool,
        badges: [String]
    ) -> [ModelMetadataRowSurface] {
        var state: [String] = []
        if isSelected {
            state.append("Current")
        }
        if badges.contains("Default") {
            state.append("Default")
        }
        if badges.contains("Recommended") {
            state.append("Recommended")
        }
        if isFavorite || badges.contains("Favorite") {
            state.append("Favorite")
        }
        if badges.contains("Recent") {
            state.append("Recent")
        }

        return [
            ModelMetadataRowSurface(label: "Provider", value: provider),
            ModelMetadataRowSurface(label: "Model ID", value: modelID),
            ModelMetadataRowSurface(label: "Category", value: category),
            ModelMetadataRowSurface(label: "State", value: state.isEmpty ? "Available" : unique(state).joined(separator: ", "))
        ]
    }

    private static func metadataDetails(
        provider: String,
        modelID: String,
        category: String,
        isSelected: Bool,
        isFavorite: Bool,
        badges: [String]
    ) -> [String] {
        var details = [
            "Provider: \(provider)",
            "Model ID: \(modelID)",
            "Category: \(category)"
        ]
        if isSelected {
            details.append("Current selection")
        }
        if isFavorite {
            details.append("Favorite")
        }
        for badge in badges {
            switch badge {
            case "Default":
                details.append("Default model")
            case "Recommended":
                details.append("Recommended by QuillCode")
            case "Recent":
                details.append("Recently used")
            case "Current", "Favorite":
                continue
            default:
                details.append(badge)
            }
        }
        return unique(details)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
