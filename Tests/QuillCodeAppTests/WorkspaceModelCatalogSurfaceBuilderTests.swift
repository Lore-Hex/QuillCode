import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceModelCatalogSurfaceBuilderTests: XCTestCase {
    private let defaultCatalog = TrustedRouterDefaults.normalizedModelCatalog([])

    func testModelLabelUsesBrandedCatalogNameOrCanonicalFallback() {
        let known = WorkspaceModelCatalogSurfaceBuilder(
            catalog: defaultCatalog,
            selectedModelID: "tr/synth",
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentModelIDs: []
        )
        let unknown = WorkspaceModelCatalogSurfaceBuilder(
            catalog: defaultCatalog,
            selectedModelID: "custom/edge-model",
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentModelIDs: []
        )

        XCTAssertEqual(known.modelLabel(), TrustedRouterDefaults.synthModelDisplayName)
        XCTAssertEqual(unknown.modelLabel(), "custom/edge-model")
    }

    func testCategoriesKeepFavoritesBeforeRecentsAndNormalizeModelAliases() throws {
        let builder = WorkspaceModelCatalogSurfaceBuilder(
            catalog: [
                ModelInfo(id: "tr/fast", provider: "tr", displayName: "", category: ""),
                ModelInfo(id: "moonshotai/kimi-k2.6", provider: "moonshotai", displayName: "Kimi K2.6", category: "Safety")
            ],
            selectedModelID: " /synth ",
            defaultModelID: "tr/fast",
            favoriteModelIDs: [" /synth ", "tr/synth"],
            recentModelIDs: ["moonshotai/kimi-k2.6", "/synth", "moonshotai/kimi-k2.6"],
            recentLimit: 4
        )

        let categories = builder.categories()
        XCTAssertEqual(categories.prefix(3).map(\.category), ["Favorites", "Recent", "Recommended"])

        let favorite = try XCTUnwrap(categories.first)
        XCTAssertEqual(favorite.models.map(\.id), [TrustedRouterDefaults.synthModel])
        XCTAssertEqual(favorite.models.first?.badges, ["Favorite", "Current", "Recommended"])
        XCTAssertTrue(favorite.models.first?.isFavorite == true)

        let recent = try XCTUnwrap(categories.dropFirst().first)
        XCTAssertEqual(recent.models.map(\.id), ["moonshotai/kimi-k2.6"])
        XCTAssertEqual(recent.models.first?.badges, ["Recent"])

        let defaultOption = try XCTUnwrap(categories
            .flatMap(\.models)
            .first { $0.id == TrustedRouterDefaults.fastModel })
        XCTAssertEqual(defaultOption.displayName, TrustedRouterDefaults.fastModelDisplayName)
        XCTAssertEqual(defaultOption.provider, TrustedRouterDefaults.trustedRouterProvider)
        XCTAssertTrue(defaultOption.badges.contains("Default"))
        XCTAssertTrue(defaultOption.badges.contains("Recommended"))
    }

    func testUnknownSelectedModelIsInsertedAsCurrentCategory() throws {
        let builder = WorkspaceModelCatalogSurfaceBuilder(
            catalog: defaultCatalog,
            selectedModelID: " custom/edge-model ",
            defaultModelID: TrustedRouterDefaults.defaultModel,
            favoriteModelIDs: [],
            recentModelIDs: []
        )

        let current = try XCTUnwrap(builder.categories().first { $0.category == "Current" })
        let option = try XCTUnwrap(current.models.first)

        XCTAssertEqual(option.id, "custom/edge-model")
        XCTAssertEqual(option.displayName, "Edge Model")
        XCTAssertTrue(option.isSelected)
        XCTAssertEqual(option.badges, ["Current"])
    }
}
