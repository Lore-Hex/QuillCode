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

    func testSessionUpdateSyncsVisibleBrowserNavigationBackIntoSelectedTab() throws {
        var browser = BrowserState()
        let firstTabID = browser.selectedTabID
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com/docs")), state: &browser, updateHistory: true)
        let secondTabID = WorkspaceBrowserEngine.newTab(state: &browser)
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://trustedrouter.com")), state: &browser, updateHistory: true)

        let update = BrowserSessionUpdate(
            tabs: [
                BrowserSessionTabUpdate(
                    id: firstTabID,
                    title: "Docs",
                    url: try XCTUnwrap(URL(string: "https://example.com/docs")),
                    isActive: false
                ),
                BrowserSessionTabUpdate(
                    id: secondTabID,
                    title: "Dashboard",
                    url: try XCTUnwrap(URL(string: "https://trustedrouter.com/dashboard")),
                    isActive: true
                )
            ],
            activeTabID: secondTabID
        )

        XCTAssertTrue(WorkspaceBrowserEngine.applySessionUpdate(update, state: &browser))

        XCTAssertEqual(browser.selectedTabID, secondTabID)
        XCTAssertEqual(browser.currentURL, "https://trustedrouter.com/dashboard")
        XCTAssertEqual(browser.addressDraft, "https://trustedrouter.com/dashboard")
        XCTAssertEqual(browser.title, "Dashboard")
        XCTAssertEqual(browser.status, "Synced from browser session")
        XCTAssertEqual(browser.history, [
            "https://trustedrouter.com",
            "https://trustedrouter.com/dashboard"
        ])
        XCTAssertEqual(browser.snapshot?.sourceLabel, "Web page")

        XCTAssertTrue(WorkspaceBrowserEngine.selectTab(id: firstTabID, state: &browser))
        XCTAssertEqual(browser.currentURL, "https://example.com/docs")
        XCTAssertEqual(browser.title, "Docs")
    }

    func testSessionUpdateAddsExternallyCreatedVisibleSessionTab() throws {
        var browser = BrowserState()
        let initialTabID = browser.selectedTabID
        let externalTabID = UUID()

        XCTAssertTrue(WorkspaceBrowserEngine.applySessionUpdate(
            BrowserSessionUpdate(
                tabs: [
                    BrowserSessionTabUpdate(
                        id: externalTabID,
                        title: "External",
                        url: try XCTUnwrap(URL(string: "https://example.com/external")),
                        isActive: true
                    )
                ],
                activeTabID: externalTabID
            ),
            state: &browser
        ))

        XCTAssertEqual(browser.selectedTabID, externalTabID)
        XCTAssertEqual(browser.tabs.map(\.id), [initialTabID, externalTabID])
        XCTAssertEqual(browser.currentURL, "https://example.com/external")
        XCTAssertEqual(browser.history, ["https://example.com/external"])
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

    func testTabsPreserveIndependentPageState() throws {
        var browser = BrowserState()
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com/docs")), state: &browser, updateHistory: true)
        XCTAssertTrue(WorkspaceBrowserEngine.addComment("First tab note", state: &browser))
        let firstTabID = browser.selectedTabID

        let secondTabID = WorkspaceBrowserEngine.newTab(state: &browser)
        XCTAssertEqual(browser.selectedTabID, secondTabID)
        XCTAssertNil(browser.currentURL)
        XCTAssertEqual(browser.status, "New tab")

        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "http://localhost:5173")), state: &browser, updateHistory: true)
        XCTAssertEqual(browser.currentURL, "http://localhost:5173")
        XCTAssertEqual(browser.comments, [])

        XCTAssertTrue(WorkspaceBrowserEngine.selectTab(id: firstTabID, state: &browser))
        XCTAssertEqual(browser.currentURL, "https://example.com/docs")
        XCTAssertEqual(browser.history, ["https://example.com/docs"])
        XCTAssertEqual(browser.comments.map(\.text), ["First tab note"])

        XCTAssertTrue(WorkspaceBrowserEngine.selectTab(id: secondTabID, state: &browser))
        XCTAssertEqual(browser.currentURL, "http://localhost:5173")
        XCTAssertEqual(browser.history, ["http://localhost:5173"])
        XCTAssertEqual(browser.comments, [])
    }

    func testClosingSelectedTabLoadsNeighborAndKeepsLastTabOpen() throws {
        var browser = BrowserState()
        let firstTabID = browser.selectedTabID
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)
        let secondTabID = WorkspaceBrowserEngine.newTab(state: &browser)
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://trustedrouter.com")), state: &browser, updateHistory: true)

        XCTAssertTrue(WorkspaceBrowserEngine.closeTab(id: secondTabID, state: &browser))
        XCTAssertEqual(browser.selectedTabID, firstTabID)
        XCTAssertEqual(browser.currentURL, "https://example.com")
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertFalse(WorkspaceBrowserEngine.closeTab(id: firstTabID, state: &browser))
        XCTAssertEqual(browser.tabs.count, 1)
    }
}
