import XCTest

final class ParityBrowserWorkflowGateTests: QuillCodeParityTestCase {
    func testWorkspaceModelDelegatesBrowserStateTransitions() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let browserModelText = try Self.appSourceText(named: "WorkspaceModelBrowser.swift")
        let browserSnapshotText = try Self.appSourceText(named: "WorkspaceModelBrowserSnapshots.swift")
        let engineText = try Self.appSourceText(named: "WorkspaceBrowserEngine.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceBrowserWorkflow.swift")
        let workflowTests = try Self.appTestSourceText(named: "WorkspaceBrowserWorkflowTests.swift")

        for expected in [
            "struct WorkspaceBrowserEngine",
            "static func openPage",
            "static func goBack",
            "static func goForward",
            "static func reload",
            "static func applyFetchedPage",
            "static func markSnapshotFetchFailure",
            "static func addComment"
        ] {
            Self.assertSource(engineText, contains: expected)
        }
        for expected in [
            "enum WorkspaceBrowserWorkflow",
            "WorkspaceBrowserEngine.openPage",
            "WorkspaceBrowserEngine.applyFetchedPage",
            "WorkspaceBrowserEngine.addComment"
        ] {
            Self.assertSource(workflowText, contains: expected)
        }
        Self.assertSource(modelText, contains: "func mutateBrowserState")
        for expected in [
            "mutateBrowserState",
            "WorkspaceBrowserWorkflow.openPreview",
        ] {
            Self.assertSource(browserModelText, contains: expected)
        }
        for expected in [
            "WorkspaceBrowserWorkflow.beginSnapshotFetch",
            "WorkspaceBrowserWorkflow.applySnapshotFetchSuccess",
            "WorkspaceBrowserWorkflow.applySnapshotFetchFailure"
        ] {
            Self.assertSource(browserSnapshotText, contains: expected)
        }
        for forbidden in [
            "public func openBrowserPreview(",
            "WorkspaceBrowserWorkflow.openPreview",
            "WorkspaceBrowserEngine.openPage",
            "WorkspaceBrowserEngine.applyFetchedPage",
            "WorkspaceBrowserEngine.markSnapshotFetchFailure",
            "WorkspaceBrowserEngine.addComment",
            "private func setBrowserPage",
            "private func appendBrowserHistory",
            "private func replaceCurrentBrowserHistory",
            "BrowserCommentState(url:",
            "Snapshot fetch: "
        ] {
            Self.assertSource(modelText, excludes: forbidden)
        }
        Self.assertSource(workflowTests, contains: "testStaleSnapshotFetchResultsDoNotOverwriteNewerPage")
    }

    func testWorkspaceModelDelegatesBrowserLocationResolving() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let resolverText = try Self.appSourceText(named: "WorkspaceBrowserLocationResolver.swift")
        let workflowText = try Self.appSourceText(named: "WorkspaceBrowserWorkflow.swift")

        for expected in [
            "struct WorkspaceBrowserLocationResolver",
            "func resolve(",
            "static func canFetchSnapshot",
            "static func snapshotFetchMessage"
        ] {
            Self.assertSource(resolverText, contains: expected)
        }
        Self.assertSource(workflowText, contains: "WorkspaceBrowserLocationResolver")
        for forbidden in [
            "WorkspaceBrowserLocationResolver",
            "private static func normalizedBrowserURL",
            "private static func canFetchBrowserSnapshot",
            "private static func browserSnapshotFetchMessage",
            "private static func projectFileBrowserURL"
        ] {
            Self.assertSource(modelText, excludes: forbidden)
        }
    }

    func testWorkspaceBrowserIntegrationTestsOwnModelBrowserFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let browserIntegrationTests = try Self.appTestSourceText(named: "WorkspaceBrowserIntegrationTests.swift")
        let browserFlowTests = [
            "testBrowserPreviewNormalizesURLsAndStoresComments",
            "testBrowserPreviewSupportsHistoryNavigationAndReload",
            "testBrowserPreviewFetchesReachableHTMLSnapshot",
            "testBrowserPreviewKeepsMetadataSnapshotWhenHTMLFetchFails",
            "testBrowserPreviewCapturesLiveDOMSnapshotWhenSessionIsAvailable",
            "testBrowserPreviewKeepsMetadataSnapshotWhenLiveDOMCaptureFails",
            "testComposerCanInspectCurrentBrowserPage",
            "testComposerCanOpenBrowserPage"
        ]

        for flowTest in browserFlowTests {
            Self.assertSource(browserIntegrationTests, contains: flowTest)
            Self.assertSource(modelTests, excludes: flowTest)
        }
    }
}
