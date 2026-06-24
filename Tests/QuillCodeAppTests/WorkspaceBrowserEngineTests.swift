import XCTest
@testable import QuillCodeApp

final class WorkspaceBrowserEngineTests: XCTestCase {
    func testOpenPageMaintainsHistoryAndPrunesForwardEntries() throws {
        var browser = BrowserState()

        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "http://localhost:3000")), state: &browser, updateHistory: true)
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "http://localhost:5173/dashboard")), state: &browser, updateHistory: true)

        XCTAssertEqual(browser.history, [
            "http://localhost:3000",
            "http://localhost:5173/dashboard"
        ])
        XCTAssertEqual(browser.historyIndex, 1)
        XCTAssertTrue(browser.canGoBack)
        XCTAssertFalse(browser.canGoForward)

        XCTAssertTrue(WorkspaceBrowserEngine.goBack(state: &browser))
        XCTAssertEqual(browser.currentURL, "http://localhost:3000")
        XCTAssertEqual(browser.historyIndex, 0)
        XCTAssertFalse(browser.canGoBack)
        XCTAssertTrue(browser.canGoForward)

        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)

        XCTAssertEqual(browser.currentURL, "https://example.com")
        XCTAssertEqual(browser.history, [
            "http://localhost:3000",
            "https://example.com"
        ])
        XCTAssertEqual(browser.historyIndex, 1)
        XCTAssertFalse(browser.canGoForward)
    }

    func testReloadKeepsCurrentHistoryAndMarksStatus() throws {
        var browser = BrowserState()
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)

        XCTAssertTrue(WorkspaceBrowserEngine.reload(state: &browser))

        XCTAssertEqual(browser.currentURL, "https://example.com")
        XCTAssertEqual(browser.history, ["https://example.com"])
        XCTAssertEqual(browser.historyIndex, 0)
        XCTAssertEqual(browser.status, "Reloaded")
    }

    func testFetchedPageReplacesCurrentHistoryEntry() throws {
        var browser = BrowserState()
        let originalURL = try XCTUnwrap(URL(string: "http://localhost:5173"))
        WorkspaceBrowserEngine.openPage(originalURL, state: &browser, updateHistory: true)

        WorkspaceBrowserEngine.applyFetchedPage(
            BrowserFetchedPage(
                finalURL: try XCTUnwrap(URL(string: "http://localhost:5173/dashboard")),
                statusCode: 200,
                contentType: "text/html",
                html: "<html><head><title>Dashboard</title></head><body><h1>Home</h1></body></html>"
            ),
            originalURL: originalURL,
            state: &browser
        )

        XCTAssertEqual(browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(browser.addressDraft, "http://localhost:5173/dashboard")
        XCTAssertEqual(browser.history, ["http://localhost:5173/dashboard"])
        XCTAssertEqual(browser.historyIndex, 0)
        XCTAssertEqual(browser.title, "Dashboard")
        XCTAssertEqual(browser.status, "Preview ready")
        XCTAssertEqual(browser.snapshot?.inspectionDepth, .networkHTMLSnapshot)
    }

    func testLiveDOMSnapshotReplacesCurrentHistoryEntry() throws {
        var browser = BrowserState()
        let originalURL = try XCTUnwrap(URL(string: "http://localhost:5173"))
        WorkspaceBrowserEngine.openPage(originalURL, state: &browser, updateHistory: true)

        WorkspaceBrowserEngine.applyLiveDOMSnapshot(
            BrowserLiveDOMSnapshot(
                finalURL: try XCTUnwrap(URL(string: "http://localhost:5173/dashboard")),
                title: "Rendered Dashboard",
                visibleText: "Dashboard ready",
                outline: ["H1: Rendered Dashboard"]
            ),
            originalURL: originalURL,
            state: &browser
        )

        XCTAssertEqual(browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(browser.addressDraft, "http://localhost:5173/dashboard")
        XCTAssertEqual(browser.history, ["http://localhost:5173/dashboard"])
        XCTAssertEqual(browser.historyIndex, 0)
        XCTAssertEqual(browser.title, "Rendered Dashboard")
        XCTAssertEqual(browser.status, "Preview ready")
        XCTAssertEqual(browser.snapshot?.inspectionDepth, .liveDOMSnapshot)
        XCTAssertEqual(browser.snapshot?.outline, ["H1: Rendered Dashboard"])
        XCTAssertEqual(browser.snapshot?.textSnippet, "Dashboard ready")
    }

    func testSnapshotFetchFailureKeepsSnapshotAndAddsReadableDetail() throws {
        var browser = BrowserState()
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)

        WorkspaceBrowserEngine.markSnapshotFetchFailure(BrowserPageFetchFailure.httpStatus(503), state: &browser)

        XCTAssertEqual(browser.status, "Preview ready")
        XCTAssertTrue(browser.snapshot?.details.contains("Snapshot fetch: The page returned HTTP 503.") == true)
    }

    func testLiveDOMCaptureFailureKeepsSnapshotAndAddsReadableDetail() throws {
        var browser = BrowserState()
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)

        WorkspaceBrowserEngine.markLiveDOMCaptureFailure(BrowserLiveDOMCaptureFailure.noRenderedSession, state: &browser)

        XCTAssertEqual(browser.status, "Preview ready")
        XCTAssertTrue(browser.snapshot?.details.contains("Live DOM capture: No rendered browser session is attached.") == true)
    }

    func testAddCommentTrimsTextAndRequiresCurrentURL() throws {
        var browser = BrowserState()

        XCTAssertFalse(WorkspaceBrowserEngine.addComment("No page", state: &browser))

        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)
        XCTAssertFalse(WorkspaceBrowserEngine.addComment("   ", state: &browser))
        XCTAssertTrue(WorkspaceBrowserEngine.addComment("  Check responsive state  ", state: &browser))

        XCTAssertEqual(browser.comments.count, 1)
        XCTAssertEqual(browser.comments[0].text, "Check responsive state")
        XCTAssertEqual(browser.comments[0].url, "https://example.com")
        XCTAssertEqual(browser.status, "Comment added")
    }
}
