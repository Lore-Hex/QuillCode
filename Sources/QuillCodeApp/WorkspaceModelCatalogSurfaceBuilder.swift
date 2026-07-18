import Foundation
import QuillCodeCore

struct WorkspaceModelCatalogSurfaceBuilder: Sendable, Hashable {
    var catalog: [ModelInfo]
    var selectedModelID: String
    var defaultModelID: String
    var favoriteModelIDs: [String]
    var recentModelIDs: [String]
    var recentLimit: Int

    init(
        catalog: [ModelInfo],
        selectedModelID: String,
        defaultModelID: String,
        favoriteModelIDs: [String],
        recentModelIDs: [String],
        recentLimit: Int = 4,
        restrictToE2EEligible: Bool = false
    ) {
        // The restriction must run AFTER normalization: normalizedModelCatalog merges the bundled
        // recommended set back in, so a pre-filtered input would quietly regrow non-eligible models.
        // Favorites/recents are filtered too — their option builders fall back to a synthesized
        // entry for ids missing from the catalog, which would otherwise smuggle a non-E2E model
        // into a confidential picker under "Recent".
        let normalized = TrustedRouterDefaults.normalizedModelCatalog(catalog)
        let eligible: (String) -> Bool = { id in
            !restrictToE2EEligible || TrustedRouterDefaults.isE2EEligible(id, catalog: normalized)
        }
        self.catalog = normalized.filter { eligible($0.id) }
        self.selectedModelID = TrustedRouterDefaults.canonicalModelID(selectedModelID)
        self.defaultModelID = TrustedRouterDefaults.normalizedDefaultModelID(defaultModelID)
        self.favoriteModelIDs = Self.normalizedUniqueModelIDs(favoriteModelIDs).filter(eligible)
        self.recentModelIDs = Self.normalizedUniqueModelIDs(recentModelIDs).filter(eligible)
        self.recentLimit = recentLimit
        self.selectedModelIsAdmissible = eligible(self.selectedModelID)
    }

    /// Whether the selected model may be synthesized back into the list when the catalog lacks it.
    /// Under the E2E restriction a selected model that LOST eligibility (a live-catalog refresh
    /// dropped its Confidential tier) must NOT be re-admitted as a phantom "Current" row — the
    /// picker would offer a model the setModel gate then refuses.
    private let selectedModelIsAdmissible: Bool

    func modelLabel() -> String {
        guard let model = catalog.first(where: { $0.id == selectedModelID }) else {
            let canonicalID = TrustedRouterDefaults.canonicalModelID(selectedModelID)
            // Feature-pinned routes (confidential's trustedrouter/e2e) may be missing from the LIVE
            // catalog; fall back to the bundled entry's display name before showing a raw route id
            // in the locked model chip.
            if let bundled = TrustedRouterDefaults.bundledModelCatalog.first(where: { $0.id == canonicalID }) {
                return TrustedRouterDefaults.displayLabel(for: bundled)
            }
            return canonicalID
        }
        return TrustedRouterDefaults.displayLabel(for: model)
    }

    func categories() -> [ModelCategorySurface] {
        let catalog = catalogIncludingSelectedModel()
        let favoriteIDSet = Set(favoriteModelIDs)

        var categories = Dictionary(grouping: baseOptions(from: catalog, favoriteIDs: favoriteIDSet), by: \.category)
            .map { category, models in
                ModelCategorySurface(
                    category: category,
                    models: models.sorted(by: Self.sortModelOptions)
                )
            }
            .sorted(by: Self.sortModelCategories)

        let favoriteModels = favoriteOptions(from: catalog, favoriteIDs: favoriteIDSet)
        if !favoriteModels.isEmpty {
            categories.insert(ModelCategorySurface(category: "Favorites", models: favoriteModels), at: 0)
        }

        let recentModels = recentOptions(from: catalog, excluding: favoriteIDSet)
        if !recentModels.isEmpty {
            categories.insert(ModelCategorySurface(category: "Recent", models: recentModels), at: favoriteModels.isEmpty ? 0 : 1)
        }
        return categories
    }

    func providerHealthSummary() -> ModelProviderHealthSummary {
        ModelProviderHealthSummary.summarize(catalogIncludingSelectedModel())
    }

    private func catalogIncludingSelectedModel() -> [ModelInfo] {
        guard !catalog.contains(where: { $0.id == selectedModelID }) else {
            return catalog
        }
        guard selectedModelIsAdmissible else {
            return catalog
        }
        return [Self.fallbackModelInfo(for: selectedModelID)] + catalog
    }

    private func baseOptions(from catalog: [ModelInfo], favoriteIDs: Set<String>) -> [ModelOptionSurface] {
        catalog.map {
            modelOption(for: $0, favoriteIDs: favoriteIDs)
        }
    }

    private func favoriteOptions(from catalog: [ModelInfo], favoriteIDs: Set<String>) -> [ModelOptionSurface] {
        favoriteModelIDs.compactMap { id -> ModelOptionSurface? in
            let model = catalog.first { $0.id == id } ?? Self.fallbackModelInfo(for: id)
            return modelOption(
                for: model,
                favoriteIDs: favoriteIDs,
                extraBadges: ["Favorite"]
            )
        }
    }

    private func recentOptions(from catalog: [ModelInfo], excluding favoriteIDs: Set<String>) -> [ModelOptionSurface] {
        let modelIDs = recentModelIDs
            .filter { !favoriteIDs.contains($0) }
        return Array(Self.unique(modelIDs).prefix(recentLimit)).compactMap { id -> ModelOptionSurface? in
            let model = catalog.first { $0.id == id } ?? Self.fallbackModelInfo(for: id)
            return modelOption(
                for: model,
                favoriteIDs: favoriteIDs,
                extraBadges: ["Recent"]
            )
        }
    }

    private func modelOption(
        for model: ModelInfo,
        favoriteIDs: Set<String>,
        extraBadges: [String] = []
    ) -> ModelOptionSurface {
        var badges = extraBadges
        let isFavorite = favoriteIDs.contains(model.id)
        if isFavorite {
            badges.append("Favorite")
        }
        if model.id == selectedModelID {
            badges.append("Current")
        }
        if model.id == defaultModelID {
            badges.append("Default")
        }
        if TrustedRouterDefaults.recommendedRank(for: model.id) != nil {
            badges.append("Recommended")
        }
        return ModelOptionSurface(
            model: model,
            selectedModelID: selectedModelID,
            isFavorite: isFavorite,
            badges: Self.unique(badges)
        )
    }

    private static func unique<S: Sequence>(_ values: S) -> [S.Element] where S.Element: Hashable {
        var seen = Set<S.Element>()
        var result: [S.Element] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func normalizedUniqueModelIDs(_ ids: [String]) -> [String] {
        unique(ids.compactMap { id in
            let modelID = TrustedRouterDefaults.canonicalModelID(id.trimmingCharacters(in: .whitespacesAndNewlines))
            return modelID.isEmpty ? nil : modelID
        })
    }

    private static func fallbackModelInfo(for id: String) -> ModelInfo {
        TrustedRouterDefaults.fallbackModelInfo(for: id)
    }

    private static func sortModelCategories(_ lhs: ModelCategorySurface, _ rhs: ModelCategorySurface) -> Bool {
        let lhsRank = modelCategoryRank(lhs.category)
        let rhsRank = modelCategoryRank(rhs.category)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.category < rhs.category
    }

    private static func modelCategoryRank(_ category: String) -> Int {
        switch category {
        case "Favorites":
            return -2
        case "Recent":
            return -1
        default:
            return TrustedRouterDefaults.modelCategoryRank(category)
        }
    }

    private static func sortModelOptions(_ lhs: ModelOptionSurface, _ rhs: ModelOptionSurface) -> Bool {
        TrustedRouterDefaults.compareModels(lhs.modelInfo, rhs.modelInfo)
    }
}
