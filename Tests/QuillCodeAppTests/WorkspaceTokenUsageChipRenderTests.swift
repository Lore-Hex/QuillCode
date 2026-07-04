import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class WorkspaceTokenUsageChipRenderTests: XCTestCase {
    private func makeTopBar(
        usageStatusLabel: String?,
        spendStatusLabel: String? = nil,
        spendStatusDetail: String? = nil
    ) -> TopBarSurface {
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
            usageStatusLabel: usageStatusLabel,
            spendStatusLabel: spendStatusLabel,
            spendStatusDetail: spendStatusDetail
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
        object.removeValue(forKey: "spendStatusLabel")
        object.removeValue(forKey: "spendStatusDetail")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(TopBarSurface.self, from: legacy)
        XCTAssertNil(decoded.usageStatusLabel)
        XCTAssertNil(decoded.spendStatusLabel)
        XCTAssertNil(decoded.spendStatusDetail)
    }

    func testHTMLRendererEmitsUsageChipOnlyWhenSet() {
        let withUsage = WorkspaceHTMLTopBarRenderer.render(makeTopBar(usageStatusLabel: "847 ctx · ↑500 ↓347"), commands: [])
        XCTAssertTrue(withUsage.contains(#"data-testid="top-bar-usage""#))
        XCTAssertTrue(withUsage.contains("847 ctx · ↑500 ↓347"))
        XCTAssertTrue(withUsage.contains("topbar-usage-chip"))

        let withoutUsage = WorkspaceHTMLTopBarRenderer.render(makeTopBar(usageStatusLabel: nil), commands: [])
        XCTAssertFalse(withoutUsage.contains(#"data-testid="top-bar-usage""#))
    }

    func testHTMLRendererPrefersSpendChipOverUsageChip() {
        let html = WorkspaceHTMLTopBarRenderer.render(
            makeTopBar(
                usageStatusLabel: "1.5k ctx · ↑1k ↓500",
                spendStatusLabel: "Spend $0.0050 / $1.00",
                spendStatusDetail: "$0.0050 across 1 model call · fuse $1.00. Latest usage: 1.5k ctx · ↑1k ↓500"
            ),
            commands: []
        )

        XCTAssertTrue(html.contains(#"data-testid="top-bar-spend""#))
        XCTAssertTrue(html.contains("Spend $0.0050 / $1.00"))
        XCTAssertTrue(html.contains("Latest usage: 1.5k ctx · ↑1k ↓500"))
        XCTAssertTrue(html.contains("topbar-spend-chip"))
        XCTAssertFalse(html.contains(#"data-testid="top-bar-usage""#))
    }
}
