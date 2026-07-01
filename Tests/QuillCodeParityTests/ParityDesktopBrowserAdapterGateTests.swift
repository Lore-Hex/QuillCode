import XCTest

final class ParityDesktopBrowserAdapterGateTests: QuillCodeParityTestCase {
    func testDesktopBrowserLiveDOMCaptureUsesFocusedAdapter() throws {
        let desktopText = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let browserCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopBrowserCoordinator.swift")
        let capturerText = try Self.desktopSourceText(named: "DesktopBrowserLiveDOMCapturer.swift")

        Self.assertSource(desktopText, contains: "QuillCodeDesktopBrowserCoordinator")
        Self.assertSource(desktopText, contains: "DesktopBrowserLiveDOMCapturer")
        Self.assertSource(capturerText, contains: "BrowserLiveDOMCapturing")
        Self.assertSource(capturerText, contains: "WKWebView")
        Self.assertSource(capturerText, contains: "evaluateJavaScript")
        Self.assertSource(capturerText, contains: "enum DesktopBrowserLiveDOMProfile")
        Self.assertSource(capturerText, contains: "case persistent")
        Self.assertSource(capturerText, contains: "case ephemeral")
        Self.assertSource(capturerText, contains: "profile: DesktopBrowserLiveDOMProfile = .persistent")
        Self.assertSource(capturerText, contains: "WKWebsiteDataStore")
        Self.assertSource(capturerText, contains: "return .default()")
        Self.assertSource(controllerText, contains: "browserLiveDOMCapturer")
        Self.assertSource(controllerText, contains: "browserCoordinator.openPreview")
        XCTAssertTrue(
            browserCoordinatorText.contains("refreshRenderedBrowserSnapshot(capturer: liveDOMCapturer)"),
            "Desktop browser preview coordinator should upgrade fetched snapshots with rendered live DOM when available."
        )
        Self.assertSource(controllerText, excludes: "WKWebView")
        Self.assertSource(controllerText, excludes: "evaluateJavaScript")
        Self.assertSource(controllerText, excludes: "import WebKit")
        Self.assertSource(controllerText, excludes: "document.body")
    }

    func testDesktopBrowserVisibleSessionUsesFocusedAdapter() throws {
        let desktopText = try Self.desktopSourceText()
        let controllerText = try Self.desktopSourceText(named: "QuillCodeDesktopController.swift")
        let browserCoordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopBrowserCoordinator.swift")
        let appText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let presenterText = try Self.desktopSourceText(named: "DesktopBrowserSessionPresenter.swift")
        let browserPaneText = try Self.appSourceText(named: "QuillCodeBrowserPaneView.swift")
        let browserControlsText = try Self.appSourceText(named: "QuillCodeBrowserPaneControls.swift")
        let commandCatalogText = try Self.appSourceText(named: "WorkspaceCommandStaticCatalog.swift")
        let viewCommandPlannerText = try Self.appSourceText(named: "QuillCodeWorkspaceViewCommandPlanner.swift")

        Self.assertSource(desktopText, contains: "DesktopBrowserSessionPresenter")
        Self.assertSource(presenterText, contains: "protocol DesktopBrowserSessionPresenting")
        Self.assertSource(presenterText, contains: "WKWebView")
        Self.assertSource(presenterText, contains: "configuration.websiteDataStore = .default()")
        Self.assertSource(presenterText, contains: "loadFileURL")
        Self.assertSource(presenterText, contains: "private var session: DesktopBrowserSessionWindowController?")
        Self.assertSource(presenterText, contains: "presentSession(_ snapshot: BrowserSessionSyncSnapshot)")
        Self.assertSource(presenterText, contains: "syncSession(_ snapshot: BrowserSessionSyncSnapshot)")
        Self.assertSource(presenterText, contains: "session.sync(snapshot)")
        Self.assertSource(presenterText, contains: "NSTabView")
        Self.assertSource(presenterText, contains: "func present()")
        Self.assertSource(presenterText, excludes: "sessions: [ObjectIdentifier")
        Self.assertSource(presenterText, excludes: "func openSession(url: URL)")
        Self.assertSource(controllerText, contains: "browserSessionPresenter")
        Self.assertSource(controllerText, contains: "browserCoordinator.openSession")
        Self.assertSource(controllerText, contains: "browserCoordinator.syncOpenSession")
        Self.assertSource(browserCoordinatorText, contains: "WorkspaceBrowserLocationResolver(workspaceRoot: root).resolve")
        Self.assertSource(browserCoordinatorText, contains: "BrowserSessionSyncSnapshot(browser: model.browser)")
        Self.assertSource(controllerText, contains: "func openBrowserSession()")
        Self.assertSource(appText, contains: "onOpenBrowserSession: controller.openBrowserSession")
        Self.assertSource(browserPaneText, contains: "var onOpenSession: (() -> Void)?")
        XCTAssertTrue(browserControlsText.contains(#"Button("Session", action: onOpenSession)"#), "Browser pane should expose a compact visible session action when available.")
        XCTAssertTrue(commandCatalogText.contains(#"id: "open-browser-session""#), "Command palette should expose visible browser sessions.")
        Self.assertSource(commandCatalogText, contains: "browserCanOpenSession")
        XCTAssertTrue(viewCommandPlannerText.contains(#"case "open-browser-session":"#), "Shared command routing should present visible sessions without falling through to text insertion.")
        Self.assertSource(controllerText, excludes: "WKWebView")
        Self.assertSource(controllerText, excludes: "import WebKit")
    }

}
