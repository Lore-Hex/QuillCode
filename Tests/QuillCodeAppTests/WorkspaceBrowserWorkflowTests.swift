import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceBrowserWorkflowTests: XCTestCase {
    func testOpenPreviewRecordsInvalidAddressWithoutClearingDraft() {
        var browser = BrowserState(addressDraft: "not-a-valid-target")
        var lastError: String?

        XCTAssertFalse(WorkspaceBrowserWorkflow.openPreview(
            nil,
            workspaceRoot: nil,
            browser: &browser,
            lastError: &lastError
        ))

        XCTAssertTrue(browser.isVisible)
        XCTAssertEqual(browser.addressDraft, "not-a-valid-target")
        XCTAssertEqual(browser.status, "Invalid address")
        XCTAssertEqual(lastError, WorkspaceBrowserWorkflow.invalidAddressError)
    }

    func testSnapshotFetchSuccessAppliesOnlyWhenCurrentURLStillMatches() throws {
        var browser = BrowserState()
        var lastError: String? = "old error"
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "http://localhost:5173")), state: &browser, updateHistory: true)
        let request = try XCTUnwrap(WorkspaceBrowserWorkflow.beginSnapshotFetch(browser: &browser))

        XCTAssertEqual(browser.status, "Fetching snapshot")

        let fetchedPage = BrowserFetchedPage(
            finalURL: try XCTUnwrap(URL(string: "http://localhost:5173/dashboard")),
            statusCode: 200,
            contentType: "text/html",
            html: "<html><head><title>Dashboard</title></head><body><h1>Home</h1></body></html>"
        )
        XCTAssertTrue(WorkspaceBrowserWorkflow.applySnapshotFetchSuccess(
            fetchedPage,
            request: request,
            browser: &browser,
            lastError: &lastError
        ))

        XCTAssertEqual(browser.currentURL, "http://localhost:5173/dashboard")
        XCTAssertEqual(browser.history, ["http://localhost:5173/dashboard"])
        XCTAssertEqual(browser.title, "Dashboard")
        XCTAssertEqual(browser.status, "Preview ready")
        XCTAssertNil(lastError)
    }

    func testStaleSnapshotFetchResultsDoNotOverwriteNewerPage() throws {
        var browser = BrowserState()
        var lastError: String?
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)
        let request = try XCTUnwrap(WorkspaceBrowserWorkflow.beginSnapshotFetch(browser: &browser))

        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://trustedrouter.com")), state: &browser, updateHistory: true)

        XCTAssertFalse(WorkspaceBrowserWorkflow.applySnapshotFetchSuccess(
            BrowserFetchedPage(
                finalURL: try XCTUnwrap(URL(string: "https://example.com")),
                html: "<html><head><title>Old Page</title></head><body></body></html>"
            ),
            request: request,
            browser: &browser,
            lastError: &lastError
        ))
        XCTAssertFalse(WorkspaceBrowserWorkflow.applySnapshotFetchFailure(
            BrowserPageFetchFailure.httpStatus(503),
            request: request,
            browser: &browser,
            lastError: &lastError
        ))

        XCTAssertEqual(browser.currentURL, "https://trustedrouter.com")
        XCTAssertEqual(browser.title, "trustedrouter.com")
        XCTAssertEqual(browser.status, "Preview ready")
        XCTAssertNil(lastError)
    }

    func testSnapshotFetchResultDoesNotOverwriteAfterTabSwitch() throws {
        var browser = BrowserState()
        var lastError: String?
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://example.com")), state: &browser, updateHistory: true)
        let request = try XCTUnwrap(WorkspaceBrowserWorkflow.beginSnapshotFetch(browser: &browser))

        _ = WorkspaceBrowserWorkflow.newTab(browser: &browser)
        WorkspaceBrowserEngine.openPage(try XCTUnwrap(URL(string: "https://trustedrouter.com")), state: &browser, updateHistory: true)

        XCTAssertFalse(WorkspaceBrowserWorkflow.applySnapshotFetchSuccess(
            BrowserFetchedPage(
                finalURL: try XCTUnwrap(URL(string: "https://example.com")),
                html: "<html><head><title>Old Page</title></head><body></body></html>"
            ),
            request: request,
            browser: &browser,
            lastError: &lastError
        ))

        XCTAssertEqual(browser.currentURL, "https://trustedrouter.com")
        XCTAssertEqual(browser.title, "trustedrouter.com")
        XCTAssertNil(lastError)
    }

    func testNavigationAndCommentsDelegateThroughWorkflow() throws {
        var browser = BrowserState()
        var lastError: String? = "old error"

        XCTAssertTrue(WorkspaceBrowserWorkflow.openPreview(
            "localhost:3000",
            workspaceRoot: nil,
            browser: &browser,
            lastError: &lastError
        ))
        XCTAssertTrue(WorkspaceBrowserWorkflow.openPreview(
            "localhost:5173",
            workspaceRoot: nil,
            browser: &browser,
            lastError: &lastError
        ))
        XCTAssertTrue(WorkspaceBrowserWorkflow.goBack(browser: &browser, lastError: &lastError))
        XCTAssertEqual(browser.currentURL, "http://localhost:3000")
        XCTAssertTrue(WorkspaceBrowserWorkflow.goForward(browser: &browser, lastError: &lastError))
        XCTAssertEqual(browser.currentURL, "http://localhost:5173")
        XCTAssertTrue(WorkspaceBrowserWorkflow.reload(browser: &browser, lastError: &lastError))
        XCTAssertEqual(browser.status, "Reloaded")
        XCTAssertTrue(WorkspaceBrowserWorkflow.addComment("  Check layout  ", browser: &browser))
        XCTAssertEqual(browser.comments.map(\.text), ["Check layout"])
        XCTAssertNil(lastError)
    }

    func testOpenPreviewRejectsBlockedDomainWithoutReplacingCurrentPage() throws {
        var browser = BrowserState()
        var lastError: String?
        XCTAssertTrue(WorkspaceBrowserWorkflow.openPreview(
            "https://trustedrouter.com",
            workspaceRoot: nil,
            browser: &browser,
            lastError: &lastError,
            domainPolicy: BrowserDomainPolicy(blockedDomains: ["example.com"])
        ))

        XCTAssertFalse(WorkspaceBrowserWorkflow.openPreview(
            "https://docs.example.com",
            workspaceRoot: nil,
            browser: &browser,
            lastError: &lastError,
            domainPolicy: BrowserDomainPolicy(blockedDomains: ["example.com"])
        ))

        XCTAssertEqual(browser.currentURL, "https://trustedrouter.com")
        XCTAssertEqual(browser.status, "Blocked by browser policy")
        XCTAssertEqual(lastError, "Blocked by browser policy: docs.example.com matches blocked domain example.com.")
    }

    func testSnapshotRedirectToBlockedDomainDoesNotReplaceCurrentPage() throws {
        var browser = BrowserState()
        var lastError: String?
        WorkspaceBrowserEngine.openPage(
            try XCTUnwrap(URL(string: "https://trustedrouter.com")),
            state: &browser,
            updateHistory: true
        )
        let request = try XCTUnwrap(WorkspaceBrowserWorkflow.beginSnapshotFetch(browser: &browser))

        XCTAssertTrue(WorkspaceBrowserWorkflow.applySnapshotFetchSuccess(
            BrowserFetchedPage(
                finalURL: try XCTUnwrap(URL(string: "https://blocked.example.com")),
                html: "<html><head><title>Blocked</title></head><body></body></html>"
            ),
            request: request,
            browser: &browser,
            lastError: &lastError,
            domainPolicy: BrowserDomainPolicy(blockedDomains: ["example.com"])
        ))

        XCTAssertEqual(browser.currentURL, "https://trustedrouter.com")
        XCTAssertEqual(browser.title, "trustedrouter.com")
        XCTAssertEqual(browser.status, "Blocked by browser policy")
        XCTAssertEqual(lastError, "Blocked by browser policy: blocked.example.com matches blocked domain example.com.")
    }

    func testSessionUpdateFiltersBlockedDomains() throws {
        var browser = BrowserState()
        let allowedID = UUID()
        let blockedID = UUID()

        XCTAssertTrue(WorkspaceBrowserWorkflow.applySessionUpdate(
            BrowserSessionUpdate(
                tabs: [
                    BrowserSessionTabUpdate(
                        id: allowedID,
                        title: "TrustedRouter",
                        url: try XCTUnwrap(URL(string: "https://trustedrouter.com")),
                        isActive: false
                    ),
                    BrowserSessionTabUpdate(
                        id: blockedID,
                        title: "Blocked",
                        url: try XCTUnwrap(URL(string: "https://blocked.example.com")),
                        isActive: true
                    )
                ],
                activeTabID: blockedID
            ),
            browser: &browser,
            domainPolicy: BrowserDomainPolicy(blockedDomains: ["example.com"])
        ))

        XCTAssertTrue(browser.tabs.contains { $0.id == allowedID })
        XCTAssertFalse(browser.tabs.contains { $0.id == blockedID })
        XCTAssertEqual(browser.currentURL, "https://trustedrouter.com")
        XCTAssertEqual(browser.status, "Blocked browser session domain")
    }
}
