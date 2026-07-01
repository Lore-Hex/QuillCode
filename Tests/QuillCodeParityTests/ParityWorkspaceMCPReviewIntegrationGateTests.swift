import XCTest

final class ParityWorkspaceMCPReviewIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceMCPIntegrationTestsOwnModelMCPFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let broadSurfaceTests = try Self.appTestSourceText(named: "WorkspaceSurfaceTests.swift")
        let mcpIntegrationTests = try Self.appTestSourceText(named: "WorkspaceMCPIntegrationTests.swift")

        Self.assertSource(mcpIntegrationTests, containsAll: [
            "testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses",
            "testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction",
            "testReadyMCPServerCanBeCalledFromAgentTurn",
            "testReadyMCPResourceCanBeReadFromAgentTurn",
            "testReadyMCPPromptCanBeLoadedFromAgentTurn",
            "testMCPToolCallRejectsUnadvertisedTools"
        ])
        Self.assertSource(modelTests, excludesAll: [
            "testMCPServerLifecycleStartsStopsAndStopAllTerminatesProcesses",
            "testReadyMCPServerCanBeCalledFromAgentTurn",
            "testReadyMCPResourceCanBeReadFromAgentTurn",
            "testReadyMCPPromptCanBeLoadedFromAgentTurn",
            "testMCPToolCallRejectsUnadvertisedTools"
        ])
        Self.assertSource(
            broadSurfaceTests,
            excludes: "testSurfaceShowsReadyMCPServerProbeSummaryAndStopAction"
        )
    }

    func testWorkspaceReviewIntegrationTestsOwnModelReviewFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let reviewIntegrationTests = try Self.appTestSourceText(named: "WorkspaceReviewIntegrationTests.swift")

        let reviewFlowTests = [
            "testApplyPatchToolRunRefreshesReviewDiff",
            "testRunReviewStageActionStagesFileAndRefreshesDiff",
            "testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff",
            "testAddReviewCommentAppendsThreadEventForVisibleDiffFile",
            "testRunReviewStageHunkActionStagesPatchAndRefreshesDiff"
        ]

        Self.assertSource(reviewIntegrationTests, containsAll: reviewFlowTests)
        Self.assertSource(modelTests, excludesAll: reviewFlowTests)
    }
}
