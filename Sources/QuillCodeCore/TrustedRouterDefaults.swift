import Foundation

public enum TrustedRouterDefaults {
    public static let fastModel = "trustedrouter/fast"
    public static let zeusModel = "trustedrouter/zeus"
    public static let prometheusModel = "trustedrouter/fusion"
    public static let socratesModel = "trustedrouter/socrates"
    public static let aristotleModel = "trustedrouter/aristotle"
    public static let platoModel = "trustedrouter/plato"
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
    public static let zeusModelDisplayName = "Zeus 1.0"
    public static let prometheusModelDisplayName = "Prometheus 1.0"
    public static let socratesModelDisplayName = "Socrates 1.0"
    public static let aristotleModelDisplayName = "Aristotle 1.0"
    public static let platoModelDisplayName = "Plato 1.0"
    public static let zeusSlashAlias = "/zeus"
    public static let prometheusSlashAlias = "/prometheus"
    public static let socratesSlashAlias = "/socrates"
    public static let aristotleSlashAlias = "/aristotle"
    public static let platoSlashAlias = "/plato"
    public static let trustedRouterProviderAliases: [String: String] = ["tr": trustedRouterProvider]
    public static let recommendedModelIDs = [
        fastModel,
        zeusModel,
        prometheusModel,
        socratesModel,
        aristotleModel,
        platoModel
    ]
    public static let modelIDAliases: [String: String] = [
        "fast": fastModel,
        "/fast": fastModel,
        "tr/fast": fastModel,
        "nike": fastModel,
        "/nike": fastModel,
        "nike 1.0": fastModel,
        "trustedrouter/nike": fastModel,
        "tr/nike": fastModel,
        "zeus": zeusModel,
        "/zeus": zeusModel,
        "zeus 1.0": zeusModel,
        "zeus-1.0": zeusModel,
        "trustedrouter/zeus": zeusModel,
        "tr/zeus": zeusModel,
        "deep research": zeusModel,
        "deep-research": zeusModel,
        "trustedrouter/deep-research": zeusModel,
        "tr/deep-research": zeusModel,
        "prometheus": prometheusModel,
        "/prometheus": prometheusModel,
        "prometheus 1.0": prometheusModel,
        "prometheus-1.0": prometheusModel,
        "trustedrouter/prometheus": prometheusModel,
        "tr/prometheus": prometheusModel,
        "tr/fusion": prometheusModel,
        "tr/socrates": socratesModel,
        "socrates": socratesModel,
        "socrates 1.0": socratesModel,
        "socrates-1.0": socratesModel,
        socratesSlashAlias: socratesModel,
        "trustedrouter/socrates": socratesModel,
        "aristotle": aristotleModel,
        "/aristotle": aristotleModel,
        "aristotle 1.0": aristotleModel,
        "aristotle-1.0": aristotleModel,
        "trustedrouter/aristotle": aristotleModel,
        "tr/aristotle": aristotleModel,
        "smart": aristotleModel,
        "trustedrouter/smart": aristotleModel,
        "tr/smart": aristotleModel,
        "plato": platoModel,
        "/plato": platoModel,
        "plato 1.0": platoModel,
        "plato-1.0": platoModel,
        "trustedrouter/plato": platoModel,
        "tr/plato": platoModel,
        "oss coding": platoModel,
        "oss-coding": platoModel,
        "freedom oss coding agent": platoModel
    ]
    public static let safetyPrimaryCatalogModel = "z-ai/glm-5.2"
    public static let safetyFallbackCatalogModel = "moonshotai/kimi-k2.6"
    public static let safetyReviewerModelIDs = [safetyPrimaryCatalogModel, safetyFallbackCatalogModel]
    public static let minimaxM3Model = "minimax/minimax-m3"

    public static let bundledModelCatalog: [ModelInfo] = [
        .init(id: fastModel, provider: trustedRouterProvider, displayName: fastModelDisplayName, category: recommendedCategory),
        .init(id: zeusModel, provider: trustedRouterProvider, displayName: zeusModelDisplayName, category: recommendedCategory),
        .init(id: prometheusModel, provider: trustedRouterProvider, displayName: prometheusModelDisplayName, category: recommendedCategory),
        .init(id: socratesModel, provider: trustedRouterProvider, displayName: socratesModelDisplayName, category: recommendedCategory),
        .init(id: aristotleModel, provider: trustedRouterProvider, displayName: aristotleModelDisplayName, category: recommendedCategory),
        .init(id: platoModel, provider: trustedRouterProvider, displayName: platoModelDisplayName, category: recommendedCategory),
        .init(id: minimaxM3Model, provider: "minimax", displayName: "MiniMax M3", category: "minimax"),
        .init(id: safetyPrimaryCatalogModel, provider: "z-ai", displayName: "GLM 5.2", category: safetyCategory),
        .init(id: safetyFallbackCatalogModel, provider: "moonshotai", displayName: "Kimi K2.6", category: safetyCategory)
    ]

    public static let recommendedDisplayNames: [String: String] = [
        fastModel: fastModelDisplayName,
        zeusModel: zeusModelDisplayName,
        prometheusModel: prometheusModelDisplayName,
        socratesModel: socratesModelDisplayName,
        aristotleModel: aristotleModelDisplayName,
        platoModel: platoModelDisplayName
    ]

    public static let recommendedSummaries: [String: String] = [
        fastModel: "Fast everyday agent",
        zeusModel: "Deep research agent",
        prometheusModel: "Freedom, OSS, deep research",
        socratesModel: "Coding agent",
        aristotleModel: "Smart general agent",
        platoModel: "Freedom, OSS coding agent"
    ]

    public static let recommendedCapabilitySummaries: [String: String] = [
        fastModel: "Nike 1.0 is the fast default for everyday coding, shell, and file-editing turns.",
        zeusModel: "Zeus 1.0 is built for deep research turns that need broad synthesis.",
        prometheusModel: "Prometheus 1.0 is the freedom-oriented OSS deep research model.",
        socratesModel: "Socrates 1.0 is the coding-agent model for implementation-heavy work.",
        aristotleModel: "Aristotle 1.0 is the smart general model for harder reasoning turns.",
        platoModel: "Plato 1.0 is the freedom-oriented OSS coding-agent model."
    ]

    public static let recommendedCapabilities: [String: ModelCapabilities] = [
        fastModel: ModelCapabilities(
            inputModalities: ["text"],
            outputModalities: ["text", "tool call"],
            capabilityTags: ["fast", "coding", "shell", "file editing"],
            summary: recommendedSummaries[fastModel]
        ),
        zeusModel: ModelCapabilities(
            inputModalities: ["text"],
            outputModalities: ["text", "tool call"],
            capabilityTags: ["deep research", "synthesis", "analysis"],
            summary: recommendedSummaries[zeusModel]
        ),
        prometheusModel: ModelCapabilities(
            inputModalities: ["text"],
            outputModalities: ["text", "tool call"],
            capabilityTags: ["freedom", "OSS", "deep research"],
            summary: recommendedSummaries[prometheusModel]
        ),
        socratesModel: ModelCapabilities(
            inputModalities: ["text"],
            outputModalities: ["text", "tool call"],
            capabilityTags: ["coding agent", "implementation", "tools"],
            summary: recommendedSummaries[socratesModel]
        ),
        aristotleModel: ModelCapabilities(
            inputModalities: ["text"],
            outputModalities: ["text", "tool call"],
            capabilityTags: ["smart", "reasoning", "general agent"],
            summary: recommendedSummaries[aristotleModel]
        ),
        platoModel: ModelCapabilities(
            inputModalities: ["text"],
            outputModalities: ["text", "tool call"],
            capabilityTags: ["freedom", "OSS", "coding agent"],
            summary: recommendedSummaries[platoModel]
        )
    ]

    public static func canonicalProvider(_ provider: String) -> String {
        let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        return trustedRouterProviderAliases[normalized.lowercased()] ?? normalized
    }

    public static func canonicalModelID(_ id: String) -> String {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return modelIDAliases[normalized.lowercased()] ?? normalized
    }

    public static func isRetiredRawModelID(_ id: String) -> Bool {
        let normalized = rawModelName(id).lowercased()
        let retiredBase = "synth"
        return normalized == retiredBase || normalized == retiredBase + "-code"
    }

    private static func rawModelName(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutSlash = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let parts = withoutSlash.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return withoutSlash }
        return ["tr", trustedRouterProvider].contains(parts[0].lowercased()) ? parts[1] : withoutSlash
    }

    public static func normalizedDefaultModelID(_ id: String) -> String {
        let modelID = canonicalModelID(id)
        return modelID.isEmpty || isRetiredRawModelID(modelID) ? defaultModel : modelID
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

    public static func preferredDisplayModelID(_ modelID: String) -> String {
        switch canonicalModelID(modelID) {
        case zeusModel:
            return zeusSlashAlias
        case prometheusModel:
            return prometheusSlashAlias
        case socratesModel:
            return socratesSlashAlias
        case aristotleModel:
            return aristotleSlashAlias
        case platoModel:
            return platoSlashAlias
        default:
            return canonicalModelID(modelID)
        }
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
        let fallbackCapabilities = recommendedCapabilities[modelID] ?? .init()
        return ModelInfo(
            id: modelID,
            provider: provider,
            displayName: recommendedDisplayNames[modelID] ?? (displayName.isEmpty ? Self.displayName(fromModelID: modelID) : displayName),
            category: category.isEmpty ? Self.category(forModelID: modelID, provider: provider) : category,
            capabilities: mergeCapabilities(fallbackCapabilities, with: model.capabilities)
        )
    }

    public static func normalizedModelCatalog(_ models: [ModelInfo]) -> [ModelInfo] {
        var indexByID: [String: Int] = [:]
        var catalog: [ModelInfo] = []
        for model in bundledModelCatalog + models {
            let normalized = normalizedModelInfo(model)
            if let index = indexByID[normalized.id] {
                // The first occurrence (usually a curated bundled entry) keeps its identity, while a
                // later duplicate — typically the live catalog row for the same canonical model —
                // backfills concrete metadata such as context window, pricing, status, and release
                // date without losing QuillCode's stable branded capability taxonomy.
                catalog[index].capabilities = mergeCapabilities(
                    catalog[index].capabilities,
                    with: normalized.capabilities
                )
                continue
            }
            indexByID[normalized.id] = catalog.count
            catalog.append(normalized)
        }
        return catalog.sorted(by: compareModels)
    }

    private static func mergeCapabilities(
        _ base: ModelCapabilities,
        with override: ModelCapabilities
    ) -> ModelCapabilities {
        ModelCapabilities(
            contextWindowTokens: override.contextWindowTokens ?? base.contextWindowTokens,
            inputPricePerMillionTokens: override.inputPricePerMillionTokens ?? base.inputPricePerMillionTokens,
            outputPricePerMillionTokens: override.outputPricePerMillionTokens ?? base.outputPricePerMillionTokens,
            inputModalities: mergedList(base.inputModalities, override.inputModalities),
            outputModalities: mergedList(base.outputModalities, override.outputModalities),
            capabilityTags: mergedList(base.capabilityTags, override.capabilityTags),
            status: override.status ?? base.status,
            summary: override.summary ?? base.summary,
            releaseDate: override.releaseDate ?? base.releaseDate
        )
    }

    private static func mergedList(_ base: [String], _ override: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in base + override {
            let key = value.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
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
