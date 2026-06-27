import XCTest
@testable import QuillCodeApp

final class BrowserSessionSyncSnapshotTests: XCTestCase {
    func testSnapshotIncludesOnlyNavigableTabsAndPreservesActiveTab() throws {
        var browser = BrowserState()
        let firstTabID = browser.selectedTabID
        WorkspaceBrowserEngine.openPage(
            try XCTUnwrap(URL(string: "https://example.com/docs")),
            state: &browser,
            updateHistory: true
        )
        let emptyTabID = WorkspaceBrowserEngine.newTab(state: &browser)
        let secondTabID = WorkspaceBrowserEngine.newTab(state: &browser)
        WorkspaceBrowserEngine.openPage(
            try XCTUnwrap(URL(string: "http://localhost:5173/dashboard")),
            state: &browser,
            updateHistory: true
        )

        let snapshot = BrowserSessionSyncSnapshot(browser: browser)

        XCTAssertEqual(snapshot.tabs.map(\.id), [firstTabID, secondTabID])
        XCTAssertEqual(snapshot.activeTabID, secondTabID)
        XCTAssertEqual(snapshot.activeTab?.url.absoluteString, "http://localhost:5173/dashboard")
        XCTAssertEqual(snapshot.tabs.map(\.isActive), [false, true])
        XCTAssertFalse(snapshot.tabs.contains { $0.id == emptyTabID })
    }

    func testSnapshotFallsBackToFirstNavigableTabWhenActiveTabIsEmpty() throws {
        var browser = BrowserState()
        let firstTabID = browser.selectedTabID
        WorkspaceBrowserEngine.openPage(
            try XCTUnwrap(URL(string: "https://example.com")),
            state: &browser,
            updateHistory: true
        )
        _ = WorkspaceBrowserEngine.newTab(state: &browser)

        let snapshot = BrowserSessionSyncSnapshot(browser: browser)

        XCTAssertEqual(snapshot.tabs.map(\.id), [firstTabID])
        XCTAssertEqual(snapshot.activeTabID, firstTabID)
        XCTAssertEqual(snapshot.activeTab?.url.absoluteString, "https://example.com")
    }

    func testManualSnapshotRejectsUnknownActiveTab() throws {
        let tab = BrowserSessionTabSnapshot(
            id: UUID(),
            title: "Docs",
            url: try XCTUnwrap(URL(string: "https://example.com")),
            isActive: false
        )

        let snapshot = BrowserSessionSyncSnapshot(tabs: [tab], activeTabID: UUID())

        XCTAssertEqual(snapshot.activeTabID, tab.id)
        XCTAssertEqual(snapshot.activeTab, tab)
    }
}
