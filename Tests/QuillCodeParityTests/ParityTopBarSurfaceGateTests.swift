import XCTest

final class ParityTopBarSurfaceGateTests: QuillCodeParityTestCase {
    func testWorkspaceSurfaceDelegatesModelCatalogBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceModelCatalogSurfaceBuilder.swift")
        let topBarBuilderText = try Self.appSourceText(named: "WorkspaceTopBarSurfaceBuilder.swift")

        [
            "struct WorkspaceModelCatalogSurfaceBuilder",
            "func modelLabel()",
            "func categories()",
            "normalizedUniqueModelIDs"
        ].forEach { Self.assertSource(builderText, contains: $0) }
        Self.assertSource(topBarBuilderText, contains: "WorkspaceModelCatalogSurfaceBuilder(")
        [
            "WorkspaceModelCatalogSurfaceBuilder(",
            "func modelCategories(selectedModelID:",
            "func modelOption(",
            "func favoriteModelIDs()",
            "func recentModelIDs("
        ].forEach { Self.assertSource(surfaceText, excludes: $0) }
    }

    func testWorkspaceSurfaceDelegatesTopBarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let topBarText = try Self.appSourceText(named: "QuillCodeTopBarSurface.swift")
        let searchFilterText = try Self.appSourceText(named: "ModelCategorySearchFilter.swift")

        [
            "public struct TopBarSurface",
            "public struct ModelCategorySurface",
            "public struct ModelMetadataRowSurface",
            "public struct ModelOptionSurface",
            "filteredModelCategories",
            "ModelCategorySearchFilter.filter"
        ].forEach { Self.assertSource(topBarText, contains: $0) }
        [
            "enum ModelCategorySearchFilter",
            "static func filter(",
            "normalizedTerms"
        ].forEach { Self.assertSource(searchFilterText, contains: $0) }
        [
            "includesFavoriteTerm",
            "metadataRows.map"
        ].forEach { Self.assertSource(topBarText, excludes: $0) }
        [
            "public struct TopBarSurface",
            "public struct ModelCategorySurface",
            "public struct ModelMetadataRowSurface",
            "public struct ModelOptionSurface",
            "filteredModelCategories"
        ].forEach { Self.assertSource(surfaceText, excludes: $0) }
    }

    func testWorkspaceSurfaceDelegatesTopBarSurfaceBuilding() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let builderText = try Self.appSourceText(named: "WorkspaceTopBarSurfaceBuilder.swift")

        Self.assertSource(surfaceText, contains: "WorkspaceTopBarSurfaceBuilder(")
        [
            "struct WorkspaceTopBarSurfaceBuilder",
            "func surface() -> TopBarSurface",
            "recentModelIDs()"
        ].forEach { Self.assertSource(builderText, contains: $0) }
        [
            "TopBarSurface(",
            "private func modelCatalogBuilder"
        ].forEach { Self.assertSource(surfaceText, excludes: $0) }
    }

    func testModelPickerWorkspaceIntegrationCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let modelPickerTests = try Self.appTestSourceText(
            named: "WorkspaceModelPickerSurfaceIntegrationTests.swift"
        )
        let topBarTests = try Self.appTestSourceText(named: "QuillCodeTopBarSurfaceTests.swift")
        let modelPickerCases = [
            "testSurfaceGroupsCustomModelCatalogByCategory",
            "testTopBarFiltersModelCatalogByProviderCategoryAndModel",
            "testSurfaceKeepsUnknownSelectedModelVisible",
            "testModelPickerShowsRecentModelsAndBadges",
            "testModelPickerShowsFavoriteModelsBeforeRecent"
        ]

        for testCase in modelPickerCases {
            Self.assertSource(modelPickerTests, contains: "func \(testCase)")
            Self.assertSource(broadSurfaceTests, excludes: "func \(testCase)")
        }
        Self.assertSource(topBarTests, contains: "func testModelOptionDecodesOlderPayloadWithoutBadges")
        Self.assertSource(
            broadSurfaceTests,
            excludes: "func testModelOptionDecodesOlderPayloadWithoutBadges"
        )
    }
}
