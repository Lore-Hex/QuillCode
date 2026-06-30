import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class WorkspaceTokenUsageLabelBuilderTests: XCTestCase {
    func testNilUsageProducesNoLabel() {
        XCTAssertNil(WorkspaceTokenUsageLabelBuilder.label(for: nil))
    }

    func testExactCountsBelowAThousand() {
        let usage = ModelTokenUsage(promptTokens: 500, completionTokens: 347)
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.label(for: usage), "847 ctx · ↑500 ↓347")
    }

    func testAbbreviatesThousandsWithOneDecimal() {
        let usage = ModelTokenUsage(promptTokens: 8100, completionTokens: 4200)
        // contextTokens == total == 12300 -> 12.3k
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.label(for: usage), "12.3k ctx · ↑8.1k ↓4.2k")
    }

    func testAbbreviatorBoundaries() {
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(0), "0")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(999), "999")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(1_000), "1k")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(1_050), "1.1k")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(1_500), "1.5k")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(12_000), "12k")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(999_949), "999.9k")
        // Rounding up at the k/m edge must roll the unit, not render "1000k".
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(999_999), "1m")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(1_000_000), "1m")
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.abbreviate(1_500_000), "1.5m")
    }

    func testZeroUsageSuppressesTheChip() {
        XCTAssertNil(WorkspaceTokenUsageLabelBuilder.label(for: ModelTokenUsage(promptTokens: 0, completionTokens: 0)))
    }

    func testContextTokensDriveTheCtxFieldIndependentlyOfPromptPlusCompletion() {
        // A provider may report a total larger than prompt+completion (cached/system tokens),
        // so ctx can exceed ↑+↓.
        let usage = ModelTokenUsage(promptTokens: 500, completionTokens: 347, totalTokens: 2_000)
        XCTAssertEqual(WorkspaceTokenUsageLabelBuilder.label(for: usage), "2k ctx · ↑500 ↓347")
    }

    func testOnlyPromptOrOnlyCompletion() {
        XCTAssertEqual(
            WorkspaceTokenUsageLabelBuilder.label(for: ModelTokenUsage(promptTokens: 120, completionTokens: 0)),
            "120 ctx · ↑120 ↓0"
        )
        XCTAssertEqual(
            WorkspaceTokenUsageLabelBuilder.label(for: ModelTokenUsage(promptTokens: 0, completionTokens: 90)),
            "90 ctx · ↑0 ↓90"
        )
    }
}
