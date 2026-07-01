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
        assertWorkspaceSurfaceAvoidsModelCatalogOwnership(surfaceText)
    }

    func testWorkspaceSurfaceDelegatesTopBarSurfaceContracts() throws {
        let surfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let topBarText = try Self.appSourceText(named: "QuillCodeTopBarSurface.swift")
        let searchFilterText = try Self.appSourceText(named: "ModelCategorySearchFilter.swift")

        assertTopBarSurfaceContracts(topBarText)
        assertModelSearchFilterContracts(searchFilterText)
        assertTopBarSurfaceAvoidsSearchPolicy(topBarText)
        assertWorkspaceSurfaceAvoidsTopBarRecords(surfaceText)
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

    private func assertWorkspaceSurfaceAvoidsModelCatalogOwnership(_ source: String) {
        [
            "WorkspaceModelCatalogSurfaceBuilder(",
            "func modelCategories(selectedModelID:",
            "func modelOption(",
            "func favoriteModelIDs()",
            "func recentModelIDs("
        ].forEach { Self.assertSource(source, excludes: $0) }
    }

    private func assertTopBarSurfaceContracts(_ source: String) {
        [
            "public struct TopBarSurface",
            "public struct ModelCategorySurface",
            "public struct ModelMetadataRowSurface",
            "public struct ModelOptionSurface",
            "filteredModelCategories",
            "ModelCategorySearchFilter.filter"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertModelSearchFilterContracts(_ source: String) {
        [
            "enum ModelCategorySearchFilter",
            "static func filter(",
            "normalizedTerms"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertTopBarSurfaceAvoidsSearchPolicy(_ source: String) {
        [
            "includesFavoriteTerm",
            "metadataRows.map"
        ].forEach { Self.assertSource(source, excludes: $0) }
    }

    private func assertWorkspaceSurfaceAvoidsTopBarRecords(_ source: String) {
        [
            "public struct TopBarSurface",
            "public struct ModelCategorySurface",
            "public struct ModelMetadataRowSurface",
            "public struct ModelOptionSurface",
            "filteredModelCategories"
        ].forEach { Self.assertSource(source, excludes: $0) }
    }
}
