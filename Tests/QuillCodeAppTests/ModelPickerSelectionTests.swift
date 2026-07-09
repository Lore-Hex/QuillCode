import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ModelPickerSelectionTests: XCTestCase {
    func testReconcilePrefersCurrentModelWhenVisible() {
        var selection = ModelPickerSelection()

        selection.reconcile(with: models(), preferredID: "moonshotai/kimi-k2.6")

        XCTAssertEqual(selection.highlightedModelID, "moonshotai/kimi-k2.6")
    }

    func testReconcileKeepsExistingHighlightWhenStillVisible() {
        var selection = ModelPickerSelection()
        selection.select(models()[1])

        selection.reconcile(with: models(), preferredID: "missing/model")

        XCTAssertEqual(selection.highlightedModelID, "moonshotai/kimi-k2.6")
    }

    func testReconcileFallsBackToFirstModelWhenHighlightDisappears() {
        var selection = ModelPickerSelection()
        selection.select(models()[2])

        selection.reconcile(with: Array(models().prefix(2)))

        XCTAssertEqual(selection.highlightedModelID, "trustedrouter/fast")
    }

    func testReconcileClearsHighlightWhenNoModelsRemain() {
        var selection = ModelPickerSelection()
        selection.select(models()[0])

        selection.reconcile(with: [])

        XCTAssertNil(selection.highlightedModelID)
    }

    func testMoveWrapsThroughVisibleModels() {
        var selection = ModelPickerSelection()
        let visible = models()
        selection.reconcile(with: visible)

        selection.move(by: -1, in: visible)
        XCTAssertEqual(selection.highlightedModelID, "minimax/minimax-m3")

        selection.move(by: 1, in: visible)
        XCTAssertEqual(selection.highlightedModelID, "trustedrouter/fast")

        selection.move(by: 2, in: visible)
        XCTAssertEqual(selection.highlightedModelID, "minimax/minimax-m3")
    }

    func testSelectedModelFallsBackToFirstVisibleModel() {
        var selection = ModelPickerSelection()
        let visible = models()

        XCTAssertEqual(selection.selectedModel(in: visible)?.id, "trustedrouter/fast")

        selection.select(visible[1])
        XCTAssertEqual(selection.selectedModel(in: visible)?.id, "moonshotai/kimi-k2.6")
    }

    private func models() -> [ModelOptionSurface] {
        [
            model(id: "trustedrouter/fast", displayName: "Nike 1.0"),
            model(id: "moonshotai/kimi-k2.6", displayName: "Kimi K2.6"),
            model(id: "minimax/minimax-m3", displayName: "MiniMax M3")
        ]
    }

    private func model(id: String, displayName: String) -> ModelOptionSurface {
        ModelOptionSurface(
            model: ModelInfo(
                id: id,
                provider: String(id.split(separator: "/").first ?? ""),
                displayName: displayName,
                category: "General"
            ),
            selectedModelID: "trustedrouter/fast"
        )
    }
}
