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

    func testModelPickerKeyboardSelectionStaysFactoredAndCovered() throws {
        let pickerText = try Self.appSourceText(named: "QuillCodeModelPickerView.swift")
        let selectionText = try Self.appSourceText(named: "ModelPickerSelection.swift")
        let testsText = try Self.appTestSourceText(named: "ModelPickerSelectionTests.swift")

        [
            "struct ModelPickerSelection",
            "mutating func reconcile",
            "mutating func move",
            "func selectedModel"
        ].forEach {
            Self.assertSource(selectionText, contains: $0)
        }

        Self.assertSource(pickerText, contains: "selection.move(by:")
        Self.assertSource(pickerText, contains: ".onExitCommand")
        Self.assertSource(testsText, contains: "func testMoveWrapsThroughVisibleModels")
        Self.assertSource(
            testsText,
            contains: "func testReconcileFallsBackToFirstModelWhenHighlightDisappears"
        )
    }
}
