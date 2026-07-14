import Foundation
import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspacePullRequestReconciliationTests: XCTestCase {
    func testQueuedPullRequestRefreshesToMergedWithoutRemovingExistingWorktree() async throws {
        let fixture = try Fixture(worktreeExists: true, status: .queued)
        let merged = fixture.pullRequest(state: "MERGED")

        let shouldPollAgain = await fixture.model.reconcileSelectedPullRequestOnce {
            _, _ in GitHubPullRequestLookup(pullRequest: merged)
        }

        XCTAssertFalse(shouldPollAgain)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .merged)
        XCTAssertNotNil(fixture.model.selectedThread?.worktree)
    }

    func testQueuedPullRequestKeepsPollingWithoutPersistingUnchangedState() async throws {
        let fixture = try Fixture(worktreeExists: true, status: .queued)
        let originalUpdatedAt = try XCTUnwrap(fixture.model.selectedThread?.pullRequest?.updatedAt)
        let queued = fixture.pullRequest(state: "OPEN", autoMergeEnabled: true)

        let shouldPollAgain = await fixture.model.reconcileSelectedPullRequestOnce {
            _, _ in GitHubPullRequestLookup(pullRequest: queued)
        }

        XCTAssertTrue(shouldPollAgain)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.updatedAt, originalUpdatedAt)
    }

    func testMergedRefreshClearsOnlyAnAlreadyMissingWorktreeBinding() async throws {
        let fixture = try Fixture(worktreeExists: false, status: .queued)
        let merged = fixture.pullRequest(state: "MERGED")

        _ = await fixture.model.reconcileSelectedPullRequestOnce {
            _, _ in GitHubPullRequestLookup(pullRequest: merged)
        }

        XCTAssertNil(fixture.model.selectedThread?.worktree)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .merged)
        XCTAssertTrue(
            fixture.model.selectedThread?.events.last?.summary.contains("already-missing") == true
        )
    }

    func testPersistedMergedStateRepairsAnAlreadyMissingWorktreeAfterRelaunch() async throws {
        let fixture = try Fixture(worktreeExists: false, status: .merged)
        let merged = fixture.pullRequest(state: "MERGED")

        _ = await fixture.model.reconcileSelectedPullRequestOnce {
            _, _ in GitHubPullRequestLookup(pullRequest: merged)
        }

        XCTAssertNil(fixture.model.selectedThread?.worktree)
    }

    func testLookupFailureIsSilentAndStopsPolling() async throws {
        let fixture = try Fixture(worktreeExists: true, status: .queued)
        let originalEvents = fixture.model.selectedThread?.events

        let shouldPollAgain = await fixture.model.reconcileSelectedPullRequestOnce {
            _, _ in GitHubPullRequestLookup(pullRequest: nil, warning: "offline")
        }

        XCTAssertFalse(shouldPollAgain)
        XCTAssertNil(fixture.model.lastError)
        XCTAssertEqual(fixture.model.selectedThread?.events, originalEvents)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .queued)
    }

    func testMismatchedPullRequestHeadIsIgnored() async throws {
        let fixture = try Fixture(worktreeExists: true, status: .queued)
        let mismatched = GitBranchPublicationPullRequest(
            number: fixture.pullRequestNumber,
            title: "Other task",
            url: "https://github.test/pull/\(fixture.pullRequestNumber)",
            state: "MERGED",
            isDraft: false,
            baseBranch: "main",
            headBranch: "feature/other",
            headCommit: fixture.headCommit
        )

        let shouldPollAgain = await fixture.model.reconcileSelectedPullRequestOnce {
            _, _ in GitHubPullRequestLookup(pullRequest: mismatched)
        }

        XCTAssertFalse(shouldPollAgain)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .queued)
    }
}

@MainActor
private final class Fixture {
    let pullRequestNumber = 42
    let branch = "feature/reconcile"
    let headCommit = "abc123"
    let model: QuillCodeWorkspaceModel

    init(worktreeExists: Bool, status: PullRequestLifecycleStatus) throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-pr-reconciliation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let worktree = projectRoot.appendingPathComponent("managed", isDirectory: true)
        if worktreeExists {
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        }
        let project = ProjectRef(name: "QuillCode", path: projectRoot.path)
        var thread = ChatThread(title: "Reconcile", projectID: project.id)
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: branch,
            base: "main",
            location: .worktree
        )
        var link = Self.makePullRequest(
            number: pullRequestNumber,
            branch: branch,
            headCommit: headCommit,
            state: status == .merged ? "MERGED" : "OPEN"
        ).durableLink()
        link.status = status
        link.updatedAt = Date(timeIntervalSince1970: 100)
        thread.pullRequest = link
        model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))
    }

    func pullRequest(
        state: String,
        autoMergeEnabled: Bool = false
    ) -> GitBranchPublicationPullRequest {
        Self.makePullRequest(
            number: pullRequestNumber,
            branch: branch,
            headCommit: headCommit,
            state: state,
            autoMergeEnabled: autoMergeEnabled
        )
    }

    private static func makePullRequest(
        number: Int,
        branch: String,
        headCommit: String,
        state: String,
        autoMergeEnabled: Bool = false
    ) -> GitBranchPublicationPullRequest {
        GitBranchPublicationPullRequest(
            number: number,
            title: "Reconcile worktree",
            url: "https://github.test/pull/\(number)",
            state: state,
            isDraft: false,
            baseBranch: "main",
            headBranch: branch,
            headCommit: headCommit,
            mergeStateStatus: "CLEAN",
            autoMergeEnabled: autoMergeEnabled
        )
    }
}
