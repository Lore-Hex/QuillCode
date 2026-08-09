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

    func testDefaultSelectionBoundsBroadlyMatchingPages() {
        let lines = ["# Revenue history", "Official investor relations source"]
            + (1...600).map { index in
                index.isMultiple(of: 10)
                    ? "Quarterly revenue evidence row \(index)"
                    : "Unrelated disclosure row \(index)"
            }
        let result = WebFetchMarkdownFocus.select(
            lines.joined(separator: "\n"),
            query: "quarterly revenue"
        )
        let retainedSourceLines = result.text.split(separator: "\n").filter {
            !$0.hasPrefix("[... ")
        }

        XCTAssertTrue(result.focused)
        XCTAssertLessThanOrEqual(
            retainedSourceLines.count,
            WebFetchMarkdownFocus.defaultMaxSelectedLines
        )
        XCTAssertTrue(result.text.contains("Quarterly revenue evidence row"))
        XCTAssertTrue(result.text.contains("non-matching lines omitted"))
    }
}
