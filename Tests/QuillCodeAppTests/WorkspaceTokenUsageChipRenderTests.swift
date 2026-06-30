import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class WorkspaceTokenUsageChipRenderTests: XCTestCase {
    private func makeTopBar(usageStatusLabel: String?) -> TopBarSurface {
        TopBarSurface(
            appName: "QuillCode",
            primaryTitle: "Investigate CI",
            subtitle: "QuillCode - Auto - Nike 1.0",
            instructionLabel: "1 instruction file loaded",
            instructionSources: [],
            memoryLabel: "No memories",
            memorySources: [],
            modelLabel: "Nike 1.0",
            selectedModelID: "trustedrouter/fast",
            modelCategories: [],
            modeLabel: "Auto",
            agentStatus: "Idle",
            computerUseLabel: "Computer Use unavailable",
            showsComputerUseSetup: false,
            usageStatusLabel: usageStatusLabel
        )
    }

    func testTopBarRoundTripsUsageStatusLabel() throws {
        for label in ["847 ctx · ↑500 ↓347", nil] {
            let decoded = try JSONDecoder().decode(
                TopBarSurface.self,
                from: JSONEncoder().encode(makeTopBar(usageStatusLabel: label))
            )
            XCTAssertEqual(decoded.usageStatusLabel, label)
        }
    }

    func testTopBarDecodesLegacyJSONWithoutUsageKey() throws {
        // A persisted top bar from before this field existed must still load (key absent -> nil).
        let encoded = try JSONEncoder().encode(makeTopBar(usageStatusLabel: "847 ctx · ↑500 ↓347"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "usageStatusLabel")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TopBarSurface.self, from: legacy)
        XCTAssertNil(decoded.usageStatusLabel)
    }

    func testHTMLRendererEmitsUsageChipOnlyWhenSet() {
        let withUsage = WorkspaceHTMLTopBarRenderer.render(makeTopBar(usageStatusLabel: "847 ctx · ↑500 ↓347"), commands: [])
        XCTAssertTrue(withUsage.contains(#"data-testid="top-bar-usage""#))
        XCTAssertTrue(withUsage.contains("847 ctx · ↑500 ↓347"))
        XCTAssertTrue(withUsage.contains("topbar-usage-chip"))

        let withoutUsage = WorkspaceHTMLTopBarRenderer.render(makeTopBar(usageStatusLabel: nil), commands: [])
        XCTAssertFalse(withoutUsage.contains(#"data-testid="top-bar-usage""#))
    }
}
