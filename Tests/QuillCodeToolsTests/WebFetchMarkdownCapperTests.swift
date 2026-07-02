import XCTest
@testable import QuillCodeTools

final class WebFetchMarkdownCapperTests: XCTestCase {
    func testUnderLimitPassesThroughUnchanged() {
        let text = "# Title\n\nBody"
        let result = WebFetchMarkdownCapper.cap(text, maxLines: 100, maxBytes: 10_000)
        XCTAssertFalse(result.truncated)
        XCTAssertEqual(result.text, text)
    }

    func testOverLineLimitKeepsTheHead() {
        let text = (1...3000).map { "line\($0)" }.joined(separator: "\n")
        let result = WebFetchMarkdownCapper.cap(text, maxLines: 100, maxBytes: 1_000_000)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.contains("content truncated"))
        XCTAssertTrue(result.text.hasPrefix("line1\n"), "the head must be kept — a page's title and intro matter most")
        XCTAssertFalse(result.text.contains("line3000"), "the tail must be dropped")
    }

    func testOverByteLimitTruncatesOnCodepointBoundary() {
        let text = String(repeating: "é", count: 10_000) // 2 bytes each
        let result = WebFetchMarkdownCapper.cap(text, maxLines: 1_000_000, maxBytes: 1001)
        XCTAssertTrue(result.truncated)
        XCTAssertFalse(result.text.unicodeScalars.contains { $0.value == 0xFFFD }, "no torn codepoints")
        XCTAssertTrue(result.text.contains("content truncated"))
    }

    func testEmptyIsPassthrough() {
        XCTAssertFalse(WebFetchMarkdownCapper.cap("").truncated)
    }

    func testExactlyAtLimitsIsNotTruncated() {
        let text = (1...100).map { "l\($0)" }.joined(separator: "\n")
        let result = WebFetchMarkdownCapper.cap(text, maxLines: 100, maxBytes: 100_000)
        XCTAssertFalse(result.truncated)
    }

    func testNoteReportsTotals() {
        let text = String(repeating: "x", count: 5_000)
        let result = WebFetchMarkdownCapper.cap(text, maxLines: 10, maxBytes: 1_000)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.text.contains("5000 bytes total"))
    }
}
