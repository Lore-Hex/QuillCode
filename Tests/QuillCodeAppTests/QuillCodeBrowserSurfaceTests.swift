import XCTest
@testable import QuillCodeApp

final class QuillCodeBrowserSurfaceTests: XCTestCase {
    func testDefaultBrowserStateCannotNavigateOrReload() {
        let browser = BrowserState()

        XCTAssertFalse(browser.canGoBack)
        XCTAssertFalse(browser.canGoForward)
        XCTAssertFalse(browser.canReload)
        XCTAssertEqual(browser.title, "Browser preview")
        XCTAssertEqual(browser.status, "Ready")
    }

    func testBrowserStateNavigationFlagsRespectHistoryIndex() {
        let middle = BrowserState(
            currentURL: "https://example.com/docs",
            history: [
                "https://example.com",
                "https://example.com/docs",
                "https://example.com/blog"
            ],
            historyIndex: 1
        )

        XCTAssertTrue(middle.canGoBack)
        XCTAssertTrue(middle.canGoForward)
        XCTAssertTrue(middle.canReload)
    }

    func testBrowserStateIgnoresOutOfRangeHistoryIndex() {
        let browser = BrowserState(
            currentURL: "https://example.com",
            history: ["https://example.com"],
            historyIndex: 10
        )

        XCTAssertFalse(browser.canGoBack)
        XCTAssertFalse(browser.canGoForward)
        XCTAssertTrue(browser.canReload)
    }

    func testBrowserSnapshotDefaultsToMetadataOnlyDepth() {
        let snapshot = BrowserSnapshotState(
            sourceLabel: "example.com",
            summary: "Example page",
            details: ["HTML"],
            outline: ["h1 Example"],
            textSnippet: "Hello"
        )

        XCTAssertEqual(snapshot.inspectionDepth, .metadataOnly)
        XCTAssertEqual(snapshot.sourceLabel, "example.com")
        XCTAssertEqual(snapshot.textSnippet, "Hello")
    }
}
