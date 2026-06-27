import XCTest
@testable import QuillCodeApp

final class QuillCodeBrowserSurfaceTests: XCTestCase {
    func testDefaultBrowserStateCannotNavigateOrReload() {
        let browser = BrowserState()

        XCTAssertFalse(browser.canGoBack)
        XCTAssertFalse(browser.canGoForward)
        XCTAssertFalse(browser.canReload)
        XCTAssertFalse(browser.canCloseSelectedTab)
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertEqual(browser.tabs.first?.id, browser.selectedTabID)
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

    func testBrowserSurfaceMapsStateIntoPresentationContract() {
        let commentID = UUID()
        let browser = BrowserState(
            isVisible: true,
            addressDraft: "https://example.com",
            currentURL: "https://example.com/docs",
            history: [
                "https://example.com",
                "https://example.com/docs",
                "https://example.com/blog"
            ],
            historyIndex: 1,
            title: "Docs",
            status: "Fetched",
            snapshot: BrowserSnapshotState(
                sourceLabel: "example.com",
                inspectionDepth: .staticHTMLSnapshot,
                summary: "Documentation",
                details: ["200 OK"],
                outline: ["h1 Docs"],
                textSnippet: "Welcome"
            ),
            comments: [
                BrowserCommentState(id: commentID, url: "https://example.com/docs", text: "Check spacing")
            ]
        )

        let surface = BrowserSurface(browser: browser)

        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.addressDraft, "https://example.com")
        XCTAssertEqual(surface.currentURL, "https://example.com/docs")
        XCTAssertTrue(surface.canOpen)
        XCTAssertTrue(surface.canGoBack)
        XCTAssertTrue(surface.canGoForward)
        XCTAssertTrue(surface.canReload)
        XCTAssertEqual(surface.title, "Docs")
        XCTAssertEqual(surface.statusLabel, "Fetched")
        XCTAssertEqual(surface.snapshot?.inspectionDepthLabel, "Static HTML snapshot")
        XCTAssertEqual(surface.snapshot?.textSnippet, "Welcome")
        XCTAssertEqual(surface.comments.first?.id, commentID)
        XCTAssertEqual(surface.comments.first?.text, "Check spacing")
        XCTAssertEqual(surface.tabs.count, 1)
        XCTAssertEqual(surface.tabs.first?.id, surface.activeTabID)
        XCTAssertTrue(surface.tabs.first?.isActive == true)
        XCTAssertEqual(surface.tabs.first?.title, "Docs")
        XCTAssertEqual(surface.tabs.first?.urlLabel, "example.com")
        XCTAssertFalse(surface.canCloseActiveTab)
    }

    func testBrowserSurfaceMapsMultipleTabsIntoPresentationContract() {
        let firstID = UUID()
        let secondID = UUID()
        let browser = BrowserState(
            tabs: [
                BrowserTabState(
                    id: firstID,
                    currentURL: "https://example.com",
                    title: "Example"
                ),
                BrowserTabState(id: secondID)
            ],
            selectedTabID: secondID
        )

        let surface = BrowserSurface(browser: browser)

        XCTAssertEqual(surface.tabs.map(\.id), [firstID, secondID])
        XCTAssertEqual(surface.activeTabID, secondID)
        XCTAssertEqual(surface.tabs[0].title, "Example")
        XCTAssertEqual(surface.tabs[0].urlLabel, "example.com")
        XCTAssertFalse(surface.tabs[0].isActive)
        XCTAssertEqual(surface.tabs[1].title, "New tab")
        XCTAssertTrue(surface.tabs[1].isActive)
        XCTAssertTrue(surface.canCloseActiveTab)
        XCTAssertEqual(surface.tabs[0].selectCommandID, "browser-tab-select:\(firstID.uuidString)")
        XCTAssertEqual(surface.tabs[1].closeCommandID, "browser-tab-close:\(secondID.uuidString)")
    }
}
