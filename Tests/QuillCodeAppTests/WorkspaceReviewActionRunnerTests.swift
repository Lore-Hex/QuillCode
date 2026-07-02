import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceReviewActionRunnerTests: XCTestCase {
    func testRunExecutesActionThenDiffRefresh() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let readme = root.appendingPathComponent("README.md")
        try "# Test repo\nUpdated\n".write(to: readme, atomically: true, encoding: .utf8)
        let runner = makeRunner(
            action: WorkspaceReviewActionSurface(kind: .stage, path: "README.md"),
            workspaceRoot: root
        )

        let result = runner.run()

        XCTAssertEqual(result.recordedResults.map(\.call.name), [
            ToolDefinition.gitStage.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertEqual(result.finalStatus, TopBarAgentStatusLabel.idle)
        XCTAssertTrue(result.action.result.ok, result.action.result.error ?? "")
        let diffRefresh = try XCTUnwrap(result.diffRefresh)
        XCTAssertTrue(diffRefresh.result.ok, diffRefresh.result.error ?? "")
        XCTAssertEqual(try runGit(["status", "--short"], cwd: root), "M  README.md\n")
    }

    func testRunReportsFailedStatusWhenActionFailsButStillRefreshesDiff() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let runner = makeRunner(
            action: WorkspaceReviewActionSurface(kind: .stage, path: "missing.md"),
            workspaceRoot: root
        )

        let result = runner.run()

        XCTAssertEqual(result.recordedResults.map(\.call.name), [
            ToolDefinition.gitStage.name,
            ToolDefinition.gitDiff.name
        ])
        XCTAssertEqual(result.finalStatus, TopBarAgentStatusLabel.failed)
        XCTAssertFalse(result.action.result.ok)
        let diffRefresh = try XCTUnwrap(result.diffRefresh)
        XCTAssertTrue(diffRefresh.result.ok, diffRefresh.result.error ?? "")
    }

    private func makeRunner(
        action: WorkspaceReviewActionSurface,
        workspaceRoot: URL
    ) -> WorkspaceReviewActionRunner {
        WorkspaceReviewActionRunner(
            plan: WorkspaceReviewActionToolCallPlanner.runPlan(for: action),
            executor: WorkspaceToolCallExecutor(
                selectedProject: nil,
                browser: BrowserState(),
                browserDomainPolicy: .unrestricted,
                router: ToolRouter(workspaceRoot: workspaceRoot),
                sshRemoteShellExecutor: SSHRemoteShellExecutor()
            )
        )
    }
}
