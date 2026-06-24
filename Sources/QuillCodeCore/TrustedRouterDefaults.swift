import Foundation

public enum TrustedRouterDefaults {
    public static let fastModel = "trustedrouter/fast"
    public static let fusionModel = "tr/fusion"
    public static let defaultModel = fastModel
    public static let defaultAPIBaseURL = "https://api.trustedrouter.com/v1"
    public static let signInURL = "https://trustedrouter.com/sign-in-with-trustedrouter"
    public static let loopbackCallbackURL = "http://localhost:3000/callback"
    public static let safetyPrimaryModel = "glm-5.2"
    public static let safetyFallbackModel = "kimi-k2.6"
    public static let recommendedCategory = "Recommended"
    public static let safetyCategory = "Safety"
    public static let currentCategory = "Current"
    public static let trustedRouterProvider = "trustedrouter"
    public static let fastModelDisplayName = "Nike 1.0"
    public static let fusionModelDisplayName = "Prometheus 1.0"
    public static let trustedRouterProviderAliases: [String: String] = ["tr": trustedRouterProvider]
    public static let recommendedModelIDs = [fastModel, fusionModel]
    public static let modelIDAliases: [String: String] = [
        "tr/fast": fastModel,
        "trustedrouter/fusion": fusionModel
    ]
    public static let safetyPrimaryCatalogModel = "z-ai/glm-5.2"
    public static let safetyFallbackCatalogModel = "moonshotai/kimi-k2.6"
    public static let safetyReviewerModelIDs = [safetyPrimaryCatalogModel, safetyFallbackCatalogModel]

    public static let bundledModelCatalog: [ModelInfo] = [
        .init(id: fastModel, provider: trustedRouterProvider, displayName: fastModelDisplayName, category: recommendedCategory),
        .init(id: fusionModel, provider: trustedRouterProvider, displayName: fusionModelDisplayName, category: recommendedCategory),
        .init(id: safetyPrimaryCatalogModel, provider: "z-ai", displayName: "GLM 5.2", category: safetyCategory),
        .init(id: safetyFallbackCatalogModel, provider: "moonshotai", displayName: "Kimi K2.6", category: safetyCategory)
    ]

    public static let recommendedDisplayNames: [String: String] = [
        fastModel: fastModelDisplayName,
        fusionModel: fusionModelDisplayName
    ]

    public static func canonicalProvider(_ provider: String) -> String {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return trustedRouterProviderAliases[normalized] ?? normalized
    }

    public static func canonicalModelID(_ id: String) -> String {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return modelIDAliases[normalized] ?? normalized
    }

    public static func normalizedDefaultModelID(_ id: String) -> String {
        let modelID = canonicalModelID(id)
        return modelID.isEmpty ? defaultModel : modelID
    }

    public static func provider(fromModelID modelID: String) -> String {
        let canonicalID = canonicalModelID(modelID)
        if let prefix = canonicalID.split(separator: "/").first {
            return canonicalProvider(String(prefix))
        }
        return trustedRouterProvider
    }

    public static func displayName(fromModelID modelID: String) -> String {
        if let displayName = recommendedDisplayNames[canonicalModelID(modelID)] {
            return displayName
        }
        let raw = canonicalModelID(modelID).split(separator: "/").last.map(String.init) ?? modelID
        return raw
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    public static func category(forModelID modelID: String, provider: String) -> String {
        if isRecommendedModel(modelID) {
            return recommendedCategory
        }
        if isSafetyReviewerModel(modelID) {
            return safetyCategory
        }
        return canonicalProvider(provider)
    }

    public static func displayLabel(for model: ModelInfo) -> String {
        if let displayName = recommendedDisplayNames[canonicalModelID(model.id)] {
            return displayName
        }
        if canonicalProvider(model.provider) == trustedRouterProvider {
            return model.id
        }
        return "\(model.provider)/\(model.displayName)"
    }

    public static func recommendedRank(for modelID: String) -> Int? {
        recommendedModelIDs.firstIndex(of: canonicalModelID(modelID))
    }

    public static func modelSortKey(id: String, provider: String, displayName: String) -> ModelSortKey {
        ModelSortKey(
            recommendedRank: recommendedRank(for: id) ?? Int.max,
            provider: canonicalProvider(provider),
            displayName: displayName,
            id: canonicalModelID(id)
        )
    }

    public static func modelCategoryRank(_ category: String) -> Int {
        switch category {
        case recommendedCategory:
            return 0
        case safetyCategory:
            return 1
        default:
            return 2
        }
    }

    public static func isRecommendedModel(_ modelID: String, provider _: String? = nil) -> Bool {
        recommendedRank(for: modelID) != nil
    }

    public static func isSafetyReviewerModel(_ modelID: String) -> Bool {
        safetyReviewerModelIDs.contains(modelID)
            || modelID == safetyPrimaryModel
            || modelID == safetyFallbackModel
    }

    public static func fallbackModelInfo(for id: String, category: String = currentCategory) -> ModelInfo {
        let modelID = canonicalModelID(id)
        let provider = provider(fromModelID: modelID)
        return ModelInfo(
            id: modelID,
            provider: provider,
            displayName: displayName(fromModelID: modelID),
            category: category
        )
    }

    public static func normalizedModelInfo(_ model: ModelInfo) -> ModelInfo {
        let modelID = canonicalModelID(model.id)
        let provider = canonicalProvider(
            model.provider.isEmpty ? provider(fromModelID: modelID) : model.provider
        )
        let displayName = model.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let category = model.category
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelInfo(
            id: modelID,
            provider: provider,
            displayName: displayName.isEmpty ? Self.displayName(fromModelID: modelID) : displayName,
            category: category.isEmpty ? Self.category(forModelID: modelID, provider: provider) : category
        )
    }

    public static func normalizedModelCatalog(_ models: [ModelInfo]) -> [ModelInfo] {
        var seen = Set<String>()
        var catalog: [ModelInfo] = []
        for model in bundledModelCatalog + models {
            let normalized = normalizedModelInfo(model)
            guard seen.insert(normalized.id).inserted else { continue }
            catalog.append(normalized)
        }
        return catalog.sorted(by: compareModels)
    }

    public static func compareModelCategories(_ lhs: String, _ rhs: String) -> Bool {
        let lhsRank = modelCategoryRank(lhs)
        let rhsRank = modelCategoryRank(rhs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs < rhs
    }

    public static func compareModels(_ lhs: ModelInfo, _ rhs: ModelInfo) -> Bool {
        let lhsCategoryRank = modelCategoryRank(lhs.category)
        let rhsCategoryRank = modelCategoryRank(rhs.category)
        if lhsCategoryRank != rhsCategoryRank { return lhsCategoryRank < rhsCategoryRank }
        return modelSortKey(id: lhs.id, provider: lhs.provider, displayName: lhs.displayName)
            < modelSortKey(id: rhs.id, provider: rhs.provider, displayName: rhs.displayName)
    }
}
