import XCTest

final class ParityBrowserSessionSyncGateTests: QuillCodeParityTestCase {
    func testVisibleBrowserSessionSyncStaysBehindSnapshotContract() throws {
        let snapshotText = try Self.appSourceText(named: "BrowserSessionSyncSnapshot.swift")
        let updateText = try Self.appSourceText(named: "BrowserSessionUpdate.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceBrowserWorkflow.swift")
        let browserModelText = try Self.appSourceText(named: "WorkspaceModelBrowserSession.swift")
        let presenterText = try Self.desktopSourceText(named: "DesktopBrowserSessionPresenter.swift")
        let coordinatorText = try Self.desktopSourceText(named: "QuillCodeDesktopBrowserCoordinator.swift")
        let controllerText = try Self.desktopControllerSourceText()
        let snapshotTests = try Self.appTestSourceText(named: "BrowserSessionSyncSnapshotTests.swift")
        let engineTests = try Self.appTestSourceText(named: "WorkspaceBrowserEngineTests.swift")
        let integrationTests = try Self.appTestSourceText(named: "WorkspaceBrowserIntegrationTests.swift")

        for expected in [
            "public struct BrowserSessionSyncSnapshot",
            "public struct BrowserSessionTabSnapshot",
            "public init(browser: BrowserState)"
        ] {
            Self.assertSource(snapshotText, contains: expected)
        }
        for expected in [
            "public struct BrowserSessionUpdate",
            "public struct BrowserSessionTabUpdate",
            "public var liveDOMSnapshot",
            "tabs.first { $0.isActive }?.id"
        ] {
            Self.assertSource(updateText, contains: expected)
        }
        Self.assertSource(snapshotText, excludes: "WebKit")
        Self.assertSource(snapshotText, excludes: "AppKit")
        Self.assertSource(updateText, excludes: "WebKit")
        Self.assertSource(updateText, excludes: "AppKit")
        Self.assertSource(engineText, contains: "static func applySessionUpdate")
        Self.assertSource(workflowText, contains: "WorkspaceBrowserEngine.applySessionUpdate")
        Self.assertSource(browserModelText, contains: "public func applyBrowserSessionUpdate")
        for expected in [
            "var onSessionUpdate",
            "emitSessionUpdate()",
            "func presentSession(_ snapshot: BrowserSessionSyncSnapshot)",
            "func syncSession(_ snapshot: BrowserSessionSyncSnapshot)",
            "func goBackSession(fallback snapshot: BrowserSessionSyncSnapshot)",
            "func goForwardSession(fallback snapshot: BrowserSessionSyncSnapshot)",
            "func evaluateJavaScriptInSelectedTab(_ source: String)",
            "func reloadSession()",
            "NSTabView"
        ] {
            Self.assertSource(presenterText, contains: expected)
        }
        Self.assertSource(presenterText, excludes: "func openSession(url: URL)")
        Self.assertSource(coordinatorText, contains: "installSessionUpdateHandler")
        Self.assertSource(coordinatorText, contains: "model.applyBrowserSessionUpdate(update)")
        Self.assertSource(coordinatorText, contains: "BrowserSessionSyncSnapshot(browser: model.browser)")
        Self.assertSource(controllerText, contains: "browserCoordinator.syncOpenSession")
        Self.assertSource(controllerText, contains: "browserCoordinator.installSessionUpdateHandler")
        Self.assertSource(snapshotTests, contains: "testSnapshotIncludesOnlyNavigableTabsAndPreservesActiveTab")
        Self.assertSource(snapshotTests, contains: "testSessionUpdateRejectsUnknownActiveTab")
        Self.assertSource(
            engineTests,
            contains: "testSessionUpdateSyncsVisibleBrowserNavigationBackIntoSelectedTab"
        )
        Self.assertSource(
            engineTests,
            contains: "testSessionUpdateCanCarryRenderedLiveDOMFromVisibleBrowserSession"
        )
        Self.assertSource(integrationTests, contains: "testVisibleBrowserSessionUpdateRefreshesModelAndSurface")
        Self.assertSource(integrationTests, contains: "testVisibleBrowserSessionUpdateRefreshesRenderedSnapshotInSurface")
    }
}
