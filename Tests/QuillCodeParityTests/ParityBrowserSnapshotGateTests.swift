import XCTest

final class ParityBrowserSnapshotGateTests: QuillCodeParityTestCase {
    func testBrowserInspectorDelegatesStaticHTMLSnapshotExtraction() throws {
        let inspectorText = try Self.appSourceText(named: "BrowserInspector.swift")
        let builderText = try Self.appSourceText(named: "BrowserHTMLSnapshotBuilder.swift")
        let builderTests = try Self.appTestSourceText(named: "BrowserHTMLSnapshotBuilderTests.swift")

        for expected in [
            "enum BrowserHTMLSnapshotBuilder",
            "static func snapshot(",
            "private static func htmlOutline",
            "private static func htmlTextSnippet"
        ] {
            Self.assertSource(builderText, contains: expected)
        }
        Self.assertSource(inspectorText, contains: "BrowserHTMLSnapshotBuilder.snapshot")
        Self.assertSource(inspectorText, excludes: "private static func htmlOutline")
        Self.assertSource(inspectorText, excludes: "private static func cleanHTMLText")
        Self.assertSource(builderTests, contains: "testSnapshotExtractsDetailsOutlineAndReadableText")
        Self.assertSource(builderTests, contains: "testSnapshotLimitsOutlineAndTruncatesSnippet")
    }

    func testBrowserLiveDOMCaptureStaysBehindAdapterContract() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let browserModelText = try Self.appSourceText(named: "WorkspaceModelBrowser.swift")
        let browserSnapshotText = try Self.appSourceText(named: "WorkspaceModelBrowserSnapshots.swift")
        let contractText = try Self.appSourceText(named: "BrowserLiveDOMCapturing.swift")
        let builderText = try Self.appSourceText(named: "BrowserLiveDOMSnapshotBuilder.swift")
        let inspectorText = try Self.appSourceText(named: "BrowserInspector.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceBrowserWorkflow.swift")
        let builderTests = try Self.appTestSourceText(named: "BrowserLiveDOMSnapshotBuilderTests.swift")
        let engineTests = try Self.appTestSourceText(named: "WorkspaceBrowserEngineTests.swift")
        let integrationTests = try Self.appTestSourceText(named: "WorkspaceBrowserIntegrationTests.swift")

        Self.assertSource(contractText, contains: "public protocol BrowserLiveDOMCapturing")
        Self.assertSource(contractText, contains: "public struct BrowserLiveDOMSnapshot")
        Self.assertSource(builderText, contains: "enum BrowserLiveDOMSnapshotBuilder")
        Self.assertSource(builderText, contains: "BrowserHTMLSnapshotBuilder.snapshot")
        Self.assertSource(inspectorText, contains: "BrowserLiveDOMSnapshotBuilder.snapshot")
        Self.assertSource(engineText, contains: "static func applyLiveDOMSnapshot")
        Self.assertSource(engineText, contains: "static func markLiveDOMCaptureFailure")
        for expected in [
            "static func beginLiveDOMCapture",
            "applyLiveDOMCaptureSuccess",
            "applyLiveDOMCaptureFailure"
        ] {
            Self.assertSource(workflowText, contains: expected)
        }
        Self.assertSource(browserSnapshotText, contains: "any BrowserLiveDOMCapturing")
        Self.assertSource(browserModelText, excludes: "any BrowserLiveDOMCapturing")
        Self.assertSource(builderTests, contains: "testLiveDOMSnapshotPrefersRenderedOutlineAndVisibleText")
        Self.assertSource(engineTests, contains: "testLiveDOMSnapshotReplacesCurrentHistoryEntry")
        Self.assertSource(
            integrationTests,
            contains: "testBrowserPreviewCapturesLiveDOMSnapshotWhenSessionIsAvailable"
        )
        Self.assertSource(modelText, excludes: "BrowserLiveDOMSnapshotBuilder.snapshot")
        Self.assertSource(modelText, excludes: "WorkspaceBrowserEngine.applyLiveDOMSnapshot")
        XCTAssertNil(
            modelText.range(
                of: #"(?<![A-Za-z0-9_])BrowserLiveDOMSnapshot\("#,
                options: .regularExpression
            )
        )
        Self.assertSource(modelText, excludes: "WKWebView")
    }
}
