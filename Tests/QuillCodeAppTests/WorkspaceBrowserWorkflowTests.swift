import XCTest
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
}
