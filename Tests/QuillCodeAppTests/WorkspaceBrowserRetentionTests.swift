import XCTest
@testable import QuillCodeApp

final class WorkspaceBrowserRetentionTests: XCTestCase {
    func testImportedHistoryRetentionPreservesSelectedPageAndValidIndex() {
        let entries = (0..<300).map { "https://example.com/page/\($0)" }

        let early = WorkspaceBrowserRetentionPolicy.normalizedHistory(
            entries,
            selectedIndex: 20
        )
        XCTAssertEqual(early.entries.count, WorkspaceBrowserRetentionPolicy.maximumHistoryEntryCount)
        XCTAssertEqual(early.entries.first, "https://example.com/page/20")
        XCTAssertEqual(early.entries.last, "https://example.com/page/147")
        XCTAssertEqual(early.selectedIndex, 0)

        let later = WorkspaceBrowserRetentionPolicy.normalizedHistory(
            entries,
            selectedIndex: 220
        )
        XCTAssertEqual(later.entries.count, WorkspaceBrowserRetentionPolicy.maximumHistoryEntryCount)
        XCTAssertEqual(later.entries.first, "https://example.com/page/172")
        XCTAssertEqual(later.entries.last, "https://example.com/page/299")
        XCTAssertEqual(later.selectedIndex, 48)
        XCTAssertEqual(later.entries[later.selectedIndex ?? -1], "https://example.com/page/220")
    }

    func testLongNavigationRetainsNewestBoundedHistoryAndValidBackState() throws {
        var browser = BrowserState()
        let overflow = 37

        for index in 0..<(WorkspaceBrowserRetentionPolicy.maximumHistoryEntryCount + overflow) {
            WorkspaceBrowserEngine.openPage(
                try XCTUnwrap(URL(string: "https://example.com/page/\(index)")),
                state: &browser,
                updateHistory: true
            )
        }

        XCTAssertEqual(browser.history.count, WorkspaceBrowserRetentionPolicy.maximumHistoryEntryCount)
        XCTAssertEqual(browser.history.first, "https://example.com/page/\(overflow)")
        XCTAssertEqual(
            browser.history.last,
            "https://example.com/page/\(WorkspaceBrowserRetentionPolicy.maximumHistoryEntryCount + overflow - 1)"
        )
        XCTAssertEqual(browser.historyIndex, WorkspaceBrowserRetentionPolicy.maximumHistoryEntryCount - 1)
        XCTAssertTrue(browser.canGoBack)
        XCTAssertFalse(browser.canGoForward)
        XCTAssertEqual(browser.status, "Preview ready; older browser history released.")

        XCTAssertTrue(WorkspaceBrowserEngine.goBack(state: &browser))
        XCTAssertEqual(
            browser.currentURL,
            "https://example.com/page/\(WorkspaceBrowserRetentionPolicy.maximumHistoryEntryCount + overflow - 2)"
        )
        XCTAssertTrue(browser.canGoForward)
    }

    func testLongCommentSessionRetainsNewestCommentsAndBoundsText() throws {
        var browser = BrowserState()
        WorkspaceBrowserEngine.openPage(
            try XCTUnwrap(URL(string: "https://example.com/review")),
            state: &browser,
            updateHistory: true
        )
        let overflow = 13
        for index in 0..<(WorkspaceBrowserRetentionPolicy.maximumCommentCount + overflow) {
            XCTAssertTrue(WorkspaceBrowserEngine.addComment("Comment \(index)", state: &browser))
        }

        XCTAssertEqual(browser.comments.count, WorkspaceBrowserRetentionPolicy.maximumCommentCount)
        XCTAssertEqual(browser.comments.first?.text, "Comment \(overflow)")
        XCTAssertEqual(
            browser.comments.last?.text,
            "Comment \(WorkspaceBrowserRetentionPolicy.maximumCommentCount + overflow - 1)"
        )
        XCTAssertEqual(browser.status, "Comment added; oldest browser comment released.")

        let oversized = String(
            repeating: "x",
            count: WorkspaceBrowserRetentionPolicy.maximumCommentCharacters + 100
        )
        XCTAssertTrue(WorkspaceBrowserEngine.addComment(oversized, state: &browser))
        XCTAssertEqual(
            browser.comments.last?.text.count,
            WorkspaceBrowserRetentionPolicy.maximumCommentCharacters
        )
        XCTAssertEqual(browser.status, "Comment shortened; oldest browser comment released.")
    }

    func testRepeatedFailuresReplaceDiagnosticsInsteadOfGrowingSnapshot() throws {
        var browser = BrowserState()
        WorkspaceBrowserEngine.openPage(
            try XCTUnwrap(URL(string: "https://example.com")),
            state: &browser,
            updateHistory: true
        )

        for status in 500..<700 {
            WorkspaceBrowserEngine.markSnapshotFetchFailure(
                BrowserPageFetchFailure.httpStatus(status),
                state: &browser
            )
            WorkspaceBrowserEngine.markLiveDOMCaptureFailure(
                BrowserLiveDOMCaptureFailure.transport("capture \(status)"),
                state: &browser
            )
        }

        let details = try XCTUnwrap(browser.snapshot?.details)
        XCTAssertEqual(details.filter { $0.hasPrefix("Snapshot fetch: ") }.count, 1)
        XCTAssertEqual(details.filter { $0.hasPrefix("Live DOM capture: ") }.count, 1)
        XCTAssertTrue(details.contains("Snapshot fetch: The page returned HTTP 699."))
        XCTAssertTrue(details.contains("Live DOM capture: capture 699"))
        XCTAssertLessThanOrEqual(details.count, WorkspaceBrowserRetentionPolicy.maximumSnapshotDetailCount)
    }

    func testTabCapacityRejectsNewTabWithoutChangingSelectionAndRecoversAfterClose() throws {
        var browser = BrowserState()
        for _ in 1..<WorkspaceBrowserRetentionPolicy.maximumTabCount {
            _ = try XCTUnwrap(WorkspaceBrowserEngine.newTab(state: &browser))
        }
        let selectedAtCapacity = browser.selectedTabID

        XCTAssertEqual(browser.tabs.count, WorkspaceBrowserRetentionPolicy.maximumTabCount)
        XCTAssertFalse(browser.canCreateNewTab)
        XCTAssertNil(WorkspaceBrowserEngine.newTab(state: &browser))
        XCTAssertEqual(browser.tabs.count, WorkspaceBrowserRetentionPolicy.maximumTabCount)
        XCTAssertEqual(browser.selectedTabID, selectedAtCapacity)
        XCTAssertEqual(browser.status, WorkspaceBrowserRetentionPolicy.tabLimitStatus)

        XCTAssertTrue(WorkspaceBrowserEngine.closeTab(id: selectedAtCapacity, state: &browser))
        XCTAssertTrue(browser.canCreateNewTab)
        XCTAssertNotNil(WorkspaceBrowserEngine.newTab(state: &browser))
        XCTAssertEqual(browser.tabs.count, WorkspaceBrowserRetentionPolicy.maximumTabCount)
    }

    func testSessionUpdateCannotInsertTabBeyondCapacityOrStealSelection() throws {
        var browser = BrowserState()
        for _ in 1..<WorkspaceBrowserRetentionPolicy.maximumTabCount {
            _ = try XCTUnwrap(WorkspaceBrowserEngine.newTab(state: &browser))
        }
        let selectedAtCapacity = browser.selectedTabID
        let rejectedTabID = UUID()

        XCTAssertTrue(WorkspaceBrowserEngine.applySessionUpdate(
            BrowserSessionUpdate(
                tabs: [
                    BrowserSessionTabUpdate(
                        id: rejectedTabID,
                        title: "Rejected",
                        url: try XCTUnwrap(URL(string: "https://example.com/rejected")),
                        isActive: true
                    )
                ],
                activeTabID: rejectedTabID
            ),
            state: &browser
        ))

        XCTAssertEqual(browser.tabs.count, WorkspaceBrowserRetentionPolicy.maximumTabCount)
        XCTAssertFalse(browser.tabs.contains { $0.id == rejectedTabID })
        XCTAssertEqual(browser.selectedTabID, selectedAtCapacity)
        XCTAssertEqual(browser.status, WorkspaceBrowserRetentionPolicy.tabLimitStatus)
    }
}
