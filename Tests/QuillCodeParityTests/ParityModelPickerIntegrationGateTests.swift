import XCTest

final class ParityModelPickerIntegrationGateTests: QuillCodeParityTestCase {
    func testModelPickerWorkspaceIntegrationCoverageStaysFocused() throws {
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let modelPickerTests = try Self.appTestSourceText(
            named: "WorkspaceModelPickerSurfaceIntegrationTests.swift"
        )
        let topBarTests = try Self.appTestSourceText(named: "QuillCodeTopBarSurfaceTests.swift")

        [
            "testSurfaceGroupsCustomModelCatalogByCategory",
            "testTopBarFiltersModelCatalogByProviderCategoryAndModel",
            "testSurfaceKeepsUnknownSelectedModelVisible",
            "testModelPickerShowsRecentModelsAndBadges",
            "testModelPickerShowsFavoriteModelsBeforeRecent"
        ].forEach {
            Self.assertSource(modelPickerTests, contains: "func \($0)")
            Self.assertSource(broadSurfaceTests, excludes: "func \($0)")
        }
        Self.assertSource(
            topBarTests,
            contains: "func testModelOptionDecodesOlderPayloadWithoutBadges"
        )
        Self.assertSource(
            broadSurfaceTests,
            excludes: "func testModelOptionDecodesOlderPayloadWithoutBadges"
        )
    }
}
