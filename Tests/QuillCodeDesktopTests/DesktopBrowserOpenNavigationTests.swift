import XCTest
import QuillCodeApp
import QuillCodeCore
import QuillCodePersistence
@testable import quill_code_desktop

/// `host.browser.open` must be a REAL navigation for the agent.
///
/// Before this, `open` only mutated in-memory browser state and returned metadata
/// ("Live DOM capture is not attached yet…"). Two consequences, both fixed here:
///  1. an unattended agent could never read a page — the whole "drive any website" story was dead;
///  2. worse, `open(A)` followed by `inspect` returned the DOM of whatever *unrelated* page the
///     session window happened to be showing, with no error — silent wrong answers.
@MainActor
final class DesktopBrowserOpenNavigationTests: XCTestCase {
    func testLocalHTMLLoaderReadsPageWithoutAWebKitFileNavigation() async throws {
        let root = try makeTempDirectory()
        let page = root.appendingPathComponent("fixture.html")
        let expected = "<main data-test='local-page'>Rendered locally</main>"
        try expected.write(to: page, atomically: true, encoding: .utf8)

        XCTAssertTrue(DesktopBrowserLocalPageLoader.handles(page))
        let loadedHTML = try await DesktopBrowserLocalPageLoader.loadHTML(at: page)
        XCTAssertEqual(loadedHTML, expected)
        XCTAssertFalse(
            DesktopBrowserLocalPageLoader.handles(root.appendingPathComponent("fixture.txt"))
        )
    }

    func testLocalHTMLNavigationDoesNotCompleteWithWebViewsInitialBlankPage() async throws {
        let root = try makeTempDirectory()
        let page = root.appendingPathComponent("fixture.html")
        try "<form><input name='status' value='Lead'></form>".write(
            to: page,
            atomically: true,
            encoding: .utf8
        )
        let tabID = UUID()
        let controller = DesktopBrowserSessionWindowController(
            snapshot: BrowserSessionSyncSnapshot(
                tabs: [
                    BrowserSessionTabSnapshot(
                        id: tabID,
                        title: "fixture.html",
                        url: page,
                        isActive: true
                    ),
                ],
                activeTabID: tabID
            )
        )
        defer { controller.close() }

        let snapshot = try await controller.navigateSelectedTab(to: page)

        XCTAssertEqual(snapshot.finalURL.standardizedFileURL, page.standardizedFileURL)
        XCTAssertTrue(snapshot.html?.contains("name=\"status\"") == true, snapshot.html ?? "")
        XCTAssertTrue(snapshot.visibleText?.isEmpty == true)
    }

    func testRapidScriptUpdatesKeepRenderedDOMRefreshWorkBounded() async throws {
        let root = try makeTempDirectory()
        let page = root.appendingPathComponent("fixture.html")
        try "<main id='state'>Initial</main>".write(to: page, atomically: true, encoding: .utf8)
        let tabID = UUID()
        let controller = DesktopBrowserSessionWindowController(
            snapshot: BrowserSessionSyncSnapshot(
                tabs: [
                    BrowserSessionTabSnapshot(
                        id: tabID,
                        title: "fixture.html",
                        url: page,
                        isActive: true
                    ),
                ],
                activeTabID: tabID
            )
        )
        defer { controller.close() }
        _ = try await controller.navigateSelectedTab(to: page)

        for iteration in 0..<200 {
            _ = try await controller.evaluateJavaScriptInSelectedTab(
                "document.querySelector('#state').textContent = 'Iteration \(iteration)'"
            )
            XCTAssertLessThanOrEqual(controller.renderedSnapshotRefreshCounts.active, 1)
            XCTAssertLessThanOrEqual(controller.renderedSnapshotRefreshCounts.pending, 1)
        }
        await waitForRenderedSnapshotRefreshesToDrain(controller)

        let snapshot = try await controller.captureLiveDOMSnapshotInSelectedTab()
        XCTAssertTrue(snapshot.visibleText?.contains("Iteration 199") == true)
        XCTAssertEqual(controller.renderedSnapshotRefreshCounts.active, 0)
        XCTAssertEqual(controller.renderedSnapshotRefreshCounts.pending, 0)
    }

    func testOpenNavigatesAndReturnsTheNavigatedPagesDOM() async throws {
        let presenter = NavigationRecordingPresenter()
        let controller = try makeController(presenter: presenter)

        let result = await controller.browserCoordinator.openSessionAndCaptureLiveDOM(
            model: controller.model,
            addressDraft: "https://www.yelp.com/search?find_desc=ramen",
            workspaceRoot: try makeTempDirectory(),
            refresh: {}
        )

        let unwrapped = try XCTUnwrap(result, "a live session must produce a navigation result")
        XCTAssertTrue(unwrapped.ok, unwrapped.error ?? "")
        XCTAssertEqual(
            presenter.navigatedURLs.map(\.absoluteString),
            ["https://www.yelp.com/search?find_desc=ramen"],
            "open must actually drive the webview to the requested URL"
        )
        // The returned DOM must come from the page we navigated to.
        XCTAssertTrue(
            unwrapped.stdout.contains("yelp.com"),
            "the tool must return the navigated page's DOM, got: \(unwrapped.stdout)"
        )
        XCTAssertEqual(controller.model.browser.snapshot?.inspectionDepth, .liveDOMSnapshot)
        XCTAssertEqual(controller.model.browser.title, "Loaded www.yelp.com")
    }

    func testLocalFileOpenUsesLiveDOMWithoutSynchronousSourceInspection() async throws {
        let presenter = NavigationRecordingPresenter()
        let controller = try makeController(presenter: presenter)
        let root = try makeTempDirectory()
        let page = root.appendingPathComponent("fixture.html")
        try "<h1>Local fixture</h1>".write(to: page, atomically: true, encoding: .utf8)

        let result = await controller.browserCoordinator.openSessionAndCaptureLiveDOM(
            model: controller.model,
            addressDraft: page.absoluteString,
            workspaceRoot: root,
            refresh: {}
        )

        XCTAssertTrue(try XCTUnwrap(result).ok)
        XCTAssertEqual(controller.model.browser.snapshot?.inspectionDepth, .liveDOMSnapshot)
        XCTAssertEqual(presenter.navigatedURLs, [page.standardizedFileURL.resolvingSymlinksInPath()])
    }

    /// The silent-corruption regression: navigating to B must never return A's DOM.
    func testSecondOpenReturnsTheNewPageNotTheOldOne() async throws {
        let presenter = NavigationRecordingPresenter()
        let controller = try makeController(presenter: presenter)
        let root = try makeTempDirectory()

        _ = await controller.browserCoordinator.openSessionAndCaptureLiveDOM(
            model: controller.model,
            addressDraft: "https://www.yelp.com/biz/first",
            workspaceRoot: root,
            refresh: {}
        )
        let second = await controller.browserCoordinator.openSessionAndCaptureLiveDOM(
            model: controller.model,
            addressDraft: "https://www.opentable.com/r/second",
            workspaceRoot: root,
            refresh: {}
        )

        let unwrapped = try XCTUnwrap(second)
        XCTAssertTrue(unwrapped.stdout.contains("opentable.com"), unwrapped.stdout)
        XCTAssertFalse(
            unwrapped.stdout.contains("yelp.com"),
            "the second open must not return the first page's DOM"
        )
        XCTAssertEqual(presenter.navigatedURLs.count, 2)
    }

    /// A page that cannot load must report the real reason, not an empty success.
    func testFailedNavigationReportsTheError() async throws {
        let presenter = NavigationRecordingPresenter()
        presenter.navigationFailureMessage = "A server with the specified hostname could not be found."
        let controller = try makeController(presenter: presenter)

        let result = await controller.browserCoordinator.openSessionAndCaptureLiveDOM(
            model: controller.model,
            addressDraft: "https://no-such-host.example",
            workspaceRoot: try makeTempDirectory(),
            refresh: {}
        )

        let unwrapped = try XCTUnwrap(result)
        XCTAssertFalse(unwrapped.ok)
        XCTAssertTrue(
            unwrapped.error?.contains("could not be found") == true,
            "the platform's reason must reach the model, got: \(unwrapped.error ?? "nil")"
        )
    }

    func testSupersededNavigationReportsTheReplacementInsteadOfFallingBack() async throws {
        let presenter = NavigationRecordingPresenter()
        presenter.navigationError = .navigationSuperseded
        let controller = try makeController(presenter: presenter)

        let result = await controller.browserCoordinator.openSessionAndCaptureLiveDOM(
            model: controller.model,
            addressDraft: "https://example.com/old-request",
            workspaceRoot: try makeTempDirectory(),
            refresh: {}
        )

        let unwrapped = try XCTUnwrap(result)
        XCTAssertFalse(unwrapped.ok)
        XCTAssertEqual(
            unwrapped.error,
            "A newer browser navigation replaced the request for https://example.com/old-request."
        )
    }

    /// With no live browser surface (headless runs, the Noop presenter), the coordinator returns nil
    /// so the caller falls back to the legacy metadata path — this feature can only ADD capability.
    func testNoLiveSessionFallsBackRatherThanFailing() async throws {
        let controller = try makeController(presenter: SessionlessPresenter())

        let result = await controller.browserCoordinator.openSessionAndCaptureLiveDOM(
            model: controller.model,
            addressDraft: "https://www.yelp.com",
            workspaceRoot: try makeTempDirectory(),
            refresh: {}
        )

        XCTAssertNil(result, "no live session must fall through to the legacy executor, not error")
    }

    // MARK: - Helpers

    private func waitForRenderedSnapshotRefreshesToDrain(
        _ controller: DesktopBrowserSessionWindowController
    ) async {
        for _ in 0..<2_000 {
            let counts = controller.renderedSnapshotRefreshCounts
            if counts.active == 0, counts.pending == 0 {
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("rendered DOM refresh work did not drain")
    }

    private func makeController(
        presenter: any DesktopBrowserSessionPresenting
    ) throws -> QuillCodeDesktopController {
        let stateRoot = try makeTempDirectory().appendingPathComponent("state", isDirectory: true)
        let paths = QuillCodePaths(home: stateRoot)
        let runtimeFactory = QuillCodeRuntimeFactory(
            paths: paths,
            environment: ["QUILLCODE_USE_MOCK_LLM": "1"]
        )
        let bootstrap = QuillCodeWorkspaceBootstrap(paths: paths, runtimeFactory: runtimeFactory)
        return QuillCodeDesktopController(
            bootstrap: bootstrap,
            browserPageFetcher: URLSessionBrowserPageFetcher(),
            browserLiveDOMCapturer: nil,
            browserSessionPresenter: presenter,
            automationNotifier: SilentAutomationNotifier(),
            workspaceRoot: try makeTempDirectory()
        )
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-browser-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct SilentAutomationNotifier: QuillCodeAutomationNotifying {
    func deliver(_ report: AutomationRunReport) {}
}

/// Records navigations and returns a DOM derived from the URL, so a test can prove the returned
/// page is the one that was navigated to.
@MainActor
private final class NavigationRecordingPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?
    private(set) var navigatedURLs: [URL] = []
    var navigationFailureMessage: String?
    var navigationError: DesktopBrowserSessionScriptError?
    private var hasOpenSession = false

    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) { hasOpenSession = true }
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) { hasOpenSession = true }

    func navigateSelectedTab(to url: URL) async throws -> BrowserLiveDOMSnapshot {
        guard hasOpenSession else { throw DesktopBrowserSessionScriptError.noOpenSession }
        if let navigationError {
            throw navigationError
        }
        if let navigationFailureMessage {
            throw DesktopBrowserSessionScriptError.navigationFailed(navigationFailureMessage)
        }
        navigatedURLs.append(url)
        return BrowserLiveDOMSnapshot(
            finalURL: url,
            title: "Loaded \(url.host ?? url.absoluteString)",
            visibleText: "Rendered content for \(url.absoluteString)",
            outline: ["H1: Loaded \(url.host ?? "page")"],
            html: "<h1>Loaded \(url.host ?? "page")</h1>",
            viewportDescription: "1120x760 @2x"
        )
    }

    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func reloadSession() {}
}

/// Stands in for a headless/no-window environment: navigation always reports no session.
@MainActor
private final class SessionlessPresenter: DesktopBrowserSessionPresenting {
    var onSessionUpdate: (@MainActor (BrowserSessionUpdate) -> Void)?
    func presentSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func syncSession(_ snapshot: BrowserSessionSyncSnapshot) {}
    func navigateSelectedTab(to url: URL) async throws -> BrowserLiveDOMSnapshot {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot) {}
    func evaluateJavaScriptInSelectedTab(_ source: String) async throws -> DesktopBrowserSessionScriptResult {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func captureLiveDOMSnapshotInSelectedTab() async throws -> BrowserLiveDOMSnapshot {
        throw DesktopBrowserSessionScriptError.noOpenSession
    }
    func clickInSelectedTab(selector: String) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func typeInSelectedTab(selector: String, text: String, submit: Bool) async throws -> DesktopBrowserSessionActionResult {
        throw DesktopBrowserSessionActionError.noOpenSession
    }
    func reloadSession() {}
}
