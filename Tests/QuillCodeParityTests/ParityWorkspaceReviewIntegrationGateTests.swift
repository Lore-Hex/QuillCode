import XCTest

final class ParityWorkspaceReviewIntegrationGateTests: QuillCodeParityTestCase {
    func testWorkspaceReviewIntegrationTestsOwnModelReviewFlows() throws {
        let modelTests = try Self.appTestSourceText(named: "WorkspaceModelTests.swift")
        let reviewIntegrationTests = try Self.appTestSourceText(
            named: "WorkspaceReviewIntegrationTests.swift"
        )

        Self.assertSource(reviewIntegrationTests, containsAll: [
            "testApplyPatchToolRunRefreshesReviewDiff",
            "testRunReviewStageActionStagesFileAndRefreshesDiff",
            "testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff",
            "testAddReviewCommentAppendsThreadEventForVisibleDiffFile",
            "testRunReviewStageHunkActionStagesPatchAndRefreshesDiff"
        ])

        Self.assertSource(modelTests, excludesAll: [
            "testApplyPatchToolRunRefreshesReviewDiff",
            "testRunReviewStageActionStagesFileAndRefreshesDiff",
            "testRemoteProjectReviewStageActionRunsThroughSSHAndRefreshesDiff",
            "testAddReviewCommentAppendsThreadEventForVisibleDiffFile",
            "testRunReviewStageHunkActionStagesPatchAndRefreshesDiff"
        ])
    }
}
