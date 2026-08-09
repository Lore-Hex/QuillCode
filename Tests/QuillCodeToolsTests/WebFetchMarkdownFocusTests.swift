import XCTest
@testable import QuillCodeTools

final class WebFetchMarkdownFocusTests: XCTestCase {
    func testSelectKeepsHeadAndHighScoringEvidenceWindows() {
        let lines = ["# Quarterly filing", "Published 2026-08-08"]
            + (1...500).map { "General disclosure line \($0)" }
            + ["| Q4 FY2026 | Revenue | $42.7M |", "Source: official filing"]
        let result = WebFetchMarkdownFocus.select(
            lines.joined(separator: "\n"),
            query: "Q4 FY2026 revenue"
        )

        XCTAssertTrue(result.focused)
        XCTAssertTrue(result.text.hasPrefix("# Quarterly filing"))
        XCTAssertTrue(result.text.contains("| Q4 FY2026 | Revenue | $42.7M |"))
        XCTAssertTrue(result.text.contains("non-matching lines omitted"))
        XCTAssertLessThan(result.text.split(separator: "\n").count, 40)
    }

    func testSelectFallsBackWhenQueryHasNoMatches() {
        let text = "# Document\n\nOnly unrelated facts."
        let result = WebFetchMarkdownFocus.select(text, query: "quarterly revenue")

        XCTAssertFalse(result.focused)
        XCTAssertEqual(result.text, text)
    }
}
