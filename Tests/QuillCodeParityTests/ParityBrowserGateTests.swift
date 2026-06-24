import XCTest

final class ParityBrowserGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesBrowserSurfaceTypes() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let workspaceSurfaceText = try Self.appSourceText(named: "WorkspaceSurface.swift")
        let browserSurfaceText = try Self.appSourceText(named: "QuillCodeBrowserSurface.swift")
        let browserEngineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")

        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserState"), "Browser state should live in a focused surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserSnapshotState"), "Browser snapshot state should live in a focused surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserCommentState"), "Browser comment state should live in a focused surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserSurface"), "Browser presentation surface should live in the browser surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserSnapshotSurface"), "Browser snapshot presentation should live in the browser surface file.")
        XCTAssertTrue(browserSurfaceText.contains("public struct BrowserCommentSurface"), "Browser comment presentation should live in the browser surface file.")
        XCTAssertTrue(browserEngineText.contains("BrowserInspector.snapshot"), "Browser state transitions should own browser snapshot construction.")
        XCTAssertFalse(modelText.contains("public struct BrowserState"), "WorkspaceModel should not own browser surface state.")
        XCTAssertFalse(modelText.contains("public struct BrowserSnapshotState"), "WorkspaceModel should not own browser snapshot state.")
        XCTAssertFalse(modelText.contains("public struct BrowserCommentState"), "WorkspaceModel should not own browser comment state.")
        XCTAssertFalse(workspaceSurfaceText.contains("public struct BrowserSurface"), "WorkspaceSurface should not own browser presentation surfaces.")
        XCTAssertFalse(workspaceSurfaceText.contains("public struct BrowserSnapshotSurface"), "WorkspaceSurface should not own browser snapshot presentation.")
        XCTAssertFalse(workspaceSurfaceText.contains("public struct BrowserCommentSurface"), "WorkspaceSurface should not own browser comment presentation.")
    }

    func testBrowserInspectorDelegatesStaticHTMLSnapshotExtraction() throws {
        let inspectorText = try Self.appSourceText(named: "BrowserInspector.swift")
        let builderText = try Self.appSourceText(named: "BrowserHTMLSnapshotBuilder.swift")
        let builderTests = try Self.appTestSourceText(named: "BrowserHTMLSnapshotBuilderTests.swift")

        XCTAssertTrue(builderText.contains("enum BrowserHTMLSnapshotBuilder"), "Static HTML snapshot extraction should have a focused owner.")
        XCTAssertTrue(builderText.contains("static func snapshot("), "HTML snapshot extraction should be directly testable.")
        XCTAssertTrue(builderText.contains("private static func htmlOutline"), "HTML outline extraction should live with the HTML snapshot builder.")
        XCTAssertTrue(builderText.contains("private static func htmlTextSnippet"), "HTML text snippet extraction should live with the HTML snapshot builder.")
        XCTAssertTrue(inspectorText.contains("BrowserHTMLSnapshotBuilder.snapshot"), "BrowserInspector should delegate static HTML extraction.")
        XCTAssertFalse(inspectorText.contains("private static func htmlOutline"), "BrowserInspector should not own HTML outline extraction.")
        XCTAssertFalse(inspectorText.contains("private static func cleanHTMLText"), "BrowserInspector should not own HTML text cleanup.")
        XCTAssertTrue(builderTests.contains("testSnapshotExtractsDetailsOutlineAndReadableText"), "HTML snapshot builder behavior should have focused tests.")
        XCTAssertTrue(builderTests.contains("testSnapshotLimitsOutlineAndTruncatesSnippet"), "HTML snapshot limits should have focused tests.")
    }

    func testWorkspaceModelDelegatesBrowserStateTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceBrowserWorkflow.swift")
        let workflowTests = try Self.appTestSourceText(named: "WorkspaceBrowserWorkflowTests.swift")

        XCTAssertTrue(engineText.contains("struct WorkspaceBrowserEngine"), "Browser state transitions should live in a focused engine.")
        XCTAssertTrue(engineText.contains("static func openPage"), "Browser opening should be directly testable.")
        XCTAssertTrue(engineText.contains("static func goBack"), "Browser back navigation should be directly testable.")
        XCTAssertTrue(engineText.contains("static func goForward"), "Browser forward navigation should be directly testable.")
        XCTAssertTrue(engineText.contains("static func reload"), "Browser reload should be directly testable.")
        XCTAssertTrue(engineText.contains("static func applyFetchedPage"), "Fetched browser pages should update state through the engine.")
        XCTAssertTrue(engineText.contains("static func markSnapshotFetchFailure"), "Browser fetch failures should update state through the engine.")
        XCTAssertTrue(engineText.contains("static func addComment"), "Browser comments should be directly testable.")
        XCTAssertTrue(workflowText.contains("enum WorkspaceBrowserWorkflow"), "Browser workflow orchestration should live in a focused helper.")
        XCTAssertTrue(workflowText.contains("WorkspaceBrowserEngine.openPage"), "Browser workflow should delegate opening to the engine.")
        XCTAssertTrue(workflowText.contains("WorkspaceBrowserEngine.applyFetchedPage"), "Browser workflow should delegate fetched browser state updates.")
        XCTAssertTrue(workflowText.contains("WorkspaceBrowserEngine.addComment"), "Browser workflow should delegate browser comments.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserWorkflow.openPreview"), "WorkspaceModel should delegate browser opening workflow.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserWorkflow.beginSnapshotFetch"), "WorkspaceModel should delegate browser fetch setup.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserWorkflow.applySnapshotFetchSuccess"), "WorkspaceModel should delegate browser fetch success.")
        XCTAssertTrue(modelText.contains("WorkspaceBrowserWorkflow.applySnapshotFetchFailure"), "WorkspaceModel should delegate browser fetch failures.")
        XCTAssertTrue(workflowTests.contains("testStaleSnapshotFetchResultsDoNotOverwriteNewerPage"), "Browser workflow should have focused stale-fetch coverage.")
        XCTAssertFalse(modelText.contains("WorkspaceBrowserEngine.openPage"), "WorkspaceModel should not directly mutate browser pages.")
        XCTAssertFalse(modelText.contains("WorkspaceBrowserEngine.applyFetchedPage"), "WorkspaceModel should not directly apply fetched browser pages.")
        XCTAssertFalse(modelText.contains("WorkspaceBrowserEngine.markSnapshotFetchFailure"), "WorkspaceModel should not directly annotate browser fetch failures.")
        XCTAssertFalse(modelText.contains("WorkspaceBrowserEngine.addComment"), "WorkspaceModel should not directly construct browser comments.")
        XCTAssertFalse(modelText.contains("private func setBrowserPage"), "WorkspaceModel should not own browser page mutation.")
        XCTAssertFalse(modelText.contains("private func appendBrowserHistory"), "WorkspaceModel should not own browser history mutation.")
        XCTAssertFalse(modelText.contains("private func replaceCurrentBrowserHistory"), "WorkspaceModel should not own browser history replacement.")
        XCTAssertFalse(modelText.contains("BrowserCommentState(url:"), "WorkspaceModel should not construct browser comments directly.")
        XCTAssertFalse(modelText.contains("Snapshot fetch: "), "WorkspaceModel should not own browser fetch-failure annotation copy.")
    }

    func testWorkspaceModelDelegatesBrowserLocationResolving() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let resolverText = try Self.appSourceText(named: "WorkspaceBrowserLocationResolver.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceBrowserWorkflow.swift")

        XCTAssertTrue(resolverText.contains("struct WorkspaceBrowserLocationResolver"), "Browser URL normalization should live in a focused resolver.")
        XCTAssertTrue(resolverText.contains("func resolve("), "Browser URL resolution should be directly testable.")
        XCTAssertTrue(resolverText.contains("static func canFetchSnapshot"), "Browser snapshot eligibility should be directly testable.")
        XCTAssertTrue(resolverText.contains("static func snapshotFetchMessage"), "Browser fetch failure copy should be directly testable.")
        XCTAssertTrue(workflowText.contains("WorkspaceBrowserLocationResolver"), "Browser workflow should delegate browser URL resolution.")
        XCTAssertFalse(modelText.contains("WorkspaceBrowserLocationResolver"), "WorkspaceModel should not own browser URL resolution.")
        XCTAssertFalse(modelText.contains("private static func normalizedBrowserURL"), "WorkspaceModel should not own browser URL normalization.")
        XCTAssertFalse(modelText.contains("private static func canFetchBrowserSnapshot"), "WorkspaceModel should not own browser snapshot eligibility.")
        XCTAssertFalse(modelText.contains("private static func browserSnapshotFetchMessage"), "WorkspaceModel should not own browser fetch failure copy.")
        XCTAssertFalse(modelText.contains("private static func projectFileBrowserURL"), "WorkspaceModel should not own project file URL resolution.")
    }

    func testWorkspaceBrowserIntegrationTestsOwnModelBrowserFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let browserIntegrationTests = try Self.appTestSourceText(named: "WorkspaceBrowserIntegrationTests.swift")

        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewNormalizesURLsAndStoresComments"), "Browser preview URL and comment integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewSupportsHistoryNavigationAndReload"), "Browser history integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewFetchesReachableHTMLSnapshot"), "Browser HTML fetch integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testBrowserPreviewKeepsMetadataSnapshotWhenHTMLFetchFails"), "Browser fetch-failure fallback integration should live in focused browser integration tests.")
        XCTAssertTrue(browserIntegrationTests.contains("testComposerCanInspectCurrentBrowserPage"), "Composer browser inspection integration should live in focused browser integration tests.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewNormalizesURLsAndStoresComments"), "WorkspaceModelTests should not own browser preview URL and comment integration flows.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewSupportsHistoryNavigationAndReload"), "WorkspaceModelTests should not own browser history integration flows.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewFetchesReachableHTMLSnapshot"), "WorkspaceModelTests should not own browser HTML fetch integration flows.")
        XCTAssertFalse(modelTests.contains("testBrowserPreviewKeepsMetadataSnapshotWhenHTMLFetchFails"), "WorkspaceModelTests should not own browser fetch-failure fallback integration flows.")
        XCTAssertFalse(modelTests.contains("testComposerCanInspectCurrentBrowserPage"), "WorkspaceModelTests should not own composer browser inspection integration flows.")
    }

    func testWorkspaceHTMLRendererDelegatesBrowserRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let browserText = try Self.appSourceText(named: "WorkspaceHTMLBrowserRenderer.swift")

        XCTAssertTrue(browserText.contains("enum WorkspaceHTMLBrowserRenderer"), "HTML browser rendering should live in a focused renderer.")
        XCTAssertTrue(browserText.contains("static func render(_ browser: BrowserSurface"), "HTML browser rendering should expose a directly testable entry point.")
        XCTAssertTrue(browserText.contains("private static func renderPreview"), "Browser preview rendering should live beside browser pane HTML.")
        XCTAssertTrue(browserText.contains("private static func renderSnapshot"), "Browser snapshot rendering should live beside browser pane HTML.")
        XCTAssertTrue(browserText.contains("private static func renderComment"), "Browser comment rendering should live beside browser pane HTML.")
        XCTAssertTrue(browserText.contains("WorkspaceHTMLPrimitives.escape"), "Browser renderer should reuse shared HTML escaping.")
        XCTAssertTrue(htmlText.contains("WorkspaceHTMLBrowserRenderer.render"), "WorkspaceHTMLRenderer should delegate browser rendering.")
        XCTAssertFalse(htmlText.contains("private static func renderBrowser"), "WorkspaceHTMLRenderer should not own browser pane rendering.")
        XCTAssertFalse(htmlText.contains("browser-snapshot-outline"), "WorkspaceHTMLRenderer should not own browser snapshot outline markup.")
        XCTAssertFalse(htmlText.contains("browser-comment"), "WorkspaceHTMLRenderer should not own browser comment markup.")
    }

    func testBrowserArchitectureGatesStayOutOfBroadSuite() throws {
        let broadSuiteURL = Self.packageRoot()
            .appendingPathComponent("Tests/QuillCodeParityTests/ParityGateTests.swift")
        let broadSuiteText = try String(contentsOf: broadSuiteURL, encoding: .utf8)

        XCTAssertFalse(broadSuiteText.contains("testWorkspaceModelDelegatesBrowserSurfaceTypes"), "Browser architecture gates should stay in ParityBrowserGateTests.")
        XCTAssertFalse(broadSuiteText.contains("testWorkspaceModelDelegatesBrowserStateTransitions"), "Browser workflow gates should stay in ParityBrowserGateTests.")
        XCTAssertFalse(broadSuiteText.contains("testWorkspaceBrowserIntegrationTestsOwnModelBrowserFlows"), "Browser integration ownership gates should stay in ParityBrowserGateTests.")
        XCTAssertFalse(broadSuiteText.contains("testWorkspaceHTMLRendererDelegatesBrowserRendering"), "Browser renderer gates should stay in ParityBrowserGateTests.")
    }
}
