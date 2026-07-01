import XCTest

final class ParityBrowserGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesBrowserSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let workspaceSurfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let browserStateText = try Self.appSourceText(named: "QuillCodeBrowserState.swift")
        let browserTabStateText = try Self.appSourceText(named: "QuillCodeBrowserTabState.swift")
        let browserSnapshotStateText = try Self.appSourceText(named: "QuillCodeBrowserSnapshotState.swift")
        let browserCommentStateText = try Self.appSourceText(named: "QuillCodeBrowserCommentState.swift")
        let browserSurfaceText = try Self.appSourceText(named: "QuillCodeBrowserSurface.swift")
        let browserEngineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")

        Self.assertSource(browserStateText, contains: "public struct BrowserState")
        Self.assertSource(browserTabStateText, contains: "public struct BrowserTabState")
        Self.assertSource(browserSnapshotStateText, contains: "public struct BrowserSnapshotState")
        Self.assertSource(browserCommentStateText, contains: "public struct BrowserCommentState")
        for expected in [
            "public struct BrowserSurface",
            "public struct BrowserTabSurface",
            "public struct BrowserSnapshotSurface",
            "public struct BrowserCommentSurface"
        ] {
            Self.assertSource(browserSurfaceText, contains: expected)
            Self.assertSource(workspaceSurfaceText, excludes: expected)
        }
        Self.assertSource(browserSurfaceText, excludes: "public struct BrowserState")
        Self.assertSource(browserStateText, excludes: "public struct BrowserSurface")
        Self.assertSource(browserEngineText, contains: "BrowserInspector.snapshot")
        for expected in ["newTab", "selectTab", "closeTab"] {
            Self.assertSource(browserEngineText, contains: "static func \(expected)")
        }
        for forbidden in [
            "public struct BrowserState",
            "public struct BrowserTabState",
            "public struct BrowserSnapshotState",
            "public struct BrowserCommentState"
        ] {
            Self.assertSource(modelText, excludes: forbidden)
        }
    }

    func testBrowserArchitectureGatesStayOutOfBroadSuite() throws {
        let broadSuiteURL = Self.packageRoot()
            .appendingPathComponent("Tests/QuillCodeParityTests/ParityGateTests.swift")
        let broadSuiteText = try String(contentsOf: broadSuiteURL, encoding: .utf8)

        for forbidden in [
            "testWorkspaceModelDelegatesBrowserSurfaceTypes",
            "testBrowserLiveDOMCaptureStaysBehindAdapterContract",
            "testWorkspaceModelDelegatesBrowserStateTransitions",
            "testWorkspaceBrowserIntegrationTestsOwnModelBrowserFlows",
            "testWorkspaceHTMLRendererDelegatesBrowserRendering"
        ] {
            Self.assertSource(broadSuiteText, excludes: forbidden)
        }
    }
}
