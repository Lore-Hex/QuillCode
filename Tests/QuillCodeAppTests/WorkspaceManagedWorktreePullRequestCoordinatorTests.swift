import Foundation
import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceManagedWorktreePullRequestCoordinatorTests: XCTestCase {
    func testRefreshPersistsQueuedPullRequestStatus() throws {
        let fixture = Fixture(worktree: try makeQuillCodeTestDirectory())
        let coordinator = fixture.coordinator(
            pullRequests: [fixture.pullRequest(status: "OPEN", autoMergeEnabled: true)]
        )

        XCTAssertTrue(coordinator.refreshSelectedThread())
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .queued)
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("queued") == true)
    }

    func testLandQueuesOpenExactPublishedHeadAndRefreshesMergedState() throws {
        let fixture = Fixture(worktree: try makeQuillCodeTestDirectory())
        var calls: [ToolCall] = []
        let coordinator = fixture.coordinator(
            branchInspection: fixture.inspection(),
            pullRequests: [
                fixture.pullRequest(status: "OPEN"),
                fixture.pullRequest(status: "MERGED")
            ],
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertTrue(coordinator.landSelectedThread())
        XCTAssertEqual(calls.map(\.name), [ToolDefinition.gitPullRequestMerge.name])
        let arguments = try ToolArguments(XCTUnwrap(calls.first?.argumentsJSON))
        XCTAssertEqual(arguments.string("selector"), "42")
        XCTAssertEqual(arguments.string("method"), "squash")
        XCTAssertEqual(arguments.bool("auto"), true)
        XCTAssertEqual(arguments.bool("deleteBranch"), false)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .merged)
    }

    func testLandRequiresDurablePullRequestLink() throws {
        let fixture = Fixture(worktree: try makeQuillCodeTestDirectory())
        fixture.model.mutateSelectedThread { $0.pullRequest = nil }
        var calls: [ToolCall] = []
        let coordinator = fixture.coordinator(
            pullRequests: [],
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertFalse(coordinator.landSelectedThread())
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("Publish") == true)
    }

    func testLandRefusesDirtyBranchAndShowsGitStatus() throws {
        let fixture = Fixture(worktree: try makeQuillCodeTestDirectory())
        var calls: [ToolCall] = []
        let coordinator = fixture.coordinator(
            branchInspection: fixture.inspection(hasUncommittedChanges: true),
            pullRequests: [fixture.pullRequest(status: "OPEN")],
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertFalse(coordinator.landSelectedThread())
        XCTAssertEqual(calls.map(\.name), [ToolDefinition.gitStatus.name])
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("before landing") == true)
    }

    func testLandRefusesPullRequestHeadDriftWithoutMutation() throws {
        let fixture = Fixture(worktree: try makeQuillCodeTestDirectory())
        var calls: [ToolCall] = []
        let coordinator = fixture.coordinator(
            branchInspection: fixture.inspection(),
            pullRequests: [fixture.pullRequest(status: "OPEN", headCommit: "different")],
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertFalse(coordinator.landSelectedThread())
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("does not match") == true)
    }

    func testCleanupRemovesOnlyCleanExactMergedWorktreeAndKeepsPRHistory() throws {
        let fixture = Fixture(worktree: try makeQuillCodeTestDirectory())
        var calls: [ToolCall] = []
        let coordinator = fixture.coordinator(
            branchInspection: fixture.inspection(),
            pullRequests: [fixture.pullRequest(status: "MERGED")],
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertTrue(coordinator.cleanUpMergedSelectedThread())
        XCTAssertEqual(calls.map(\.name), [ToolDefinition.gitWorktreeRemove.name])
        let arguments = try ToolArguments(XCTUnwrap(calls.first?.argumentsJSON))
        XCTAssertEqual(arguments.string("path"), fixture.worktree.path)
        XCTAssertEqual(arguments.bool("force"), false)
        XCTAssertNil(fixture.model.selectedThread?.worktree)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .merged)
    }

    func testCleanupPreservesWorktreeWhenMergedHeadDoesNotMatch() throws {
        let fixture = Fixture(worktree: try makeQuillCodeTestDirectory())
        var calls: [ToolCall] = []
        let coordinator = fixture.coordinator(
            branchInspection: fixture.inspection(),
            pullRequests: [fixture.pullRequest(status: "MERGED", headCommit: "different")],
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertFalse(coordinator.cleanUpMergedSelectedThread())
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNotNil(fixture.model.selectedThread?.worktree)
    }

    func testCleanupClearsAlreadyMissingMergedWorktreeWithoutGitRemoval() throws {
        let parent = try makeQuillCodeTestDirectory()
        let missingWorktree = parent.appendingPathComponent("already-removed", isDirectory: true)
        let fixture = Fixture(worktree: missingWorktree)
        var calls: [ToolCall] = []
        var lookupRoot: URL?
        let coordinator = fixture.coordinator(
            pullRequests: [fixture.pullRequest(status: "MERGED")],
            inspectPullRequest: { root, _ in
                lookupRoot = root
                return GitHubPullRequestLookup(pullRequest: fixture.pullRequest(status: "MERGED"))
            },
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertTrue(coordinator.cleanUpMergedSelectedThread())
        XCTAssertEqual(lookupRoot?.standardizedFileURL, parent.standardizedFileURL)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(fixture.model.selectedThread?.worktree)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .merged)
    }
}

@MainActor
private final class Fixture {
    let worktree: URL
    let branch = "feature/land"
    let headCommit = "abc123"
    let model: QuillCodeWorkspaceModel

    init(worktree: URL) {
        self.worktree = worktree
        let project = ProjectRef(name: "QuillCode", path: worktree.deletingLastPathComponent().path)
        var thread = ChatThread(title: "Land", projectID: project.id)
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: branch,
            base: "main",
            location: .worktree
        )
        thread.pullRequest = Self.makePullRequest(
            status: "OPEN",
            branch: branch,
            headCommit: headCommit
        ).durableLink()
        model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))
    }

    func inspection(hasUncommittedChanges: Bool = false) -> GitBranchPublicationInspection {
        GitBranchPublicationInspection(
            branch: branch,
            baseBranch: "main",
            headCommit: headCommit,
            hasUncommittedChanges: hasUncommittedChanges,
            commitsAheadOfBase: 1,
            upstream: "origin/\(branch)"
        )
    }

    func pullRequest(
        status: String,
        headCommit: String? = nil,
        autoMergeEnabled: Bool = false
    ) -> GitBranchPublicationPullRequest {
        Self.makePullRequest(
            status: status,
            branch: branch,
            headCommit: headCommit ?? self.headCommit,
            autoMergeEnabled: autoMergeEnabled
        )
    }

    private static func makePullRequest(
        status: String,
        branch: String,
        headCommit: String,
        autoMergeEnabled: Bool = false
    ) -> GitBranchPublicationPullRequest {
        GitBranchPublicationPullRequest(
            number: 42,
            title: "Land worktree",
            url: "https://github.test/pull/42",
            state: status,
            isDraft: false,
            baseBranch: "main",
            headBranch: branch,
            headCommit: headCommit,
            mergeStateStatus: "CLEAN",
            autoMergeEnabled: autoMergeEnabled
        )
    }

    func coordinator(
        branchInspection: GitBranchPublicationInspection? = nil,
        pullRequests: [GitBranchPublicationPullRequest],
        inspectPullRequest: WorkspaceManagedWorktreePullRequestCoordinator.PullRequestLookupProvider? = nil,
        runTool: @escaping WorkspaceManagedWorktreePullRequestCoordinator.ToolRunner = { _, _, _ in
            ToolResult(ok: true)
        }
    ) -> WorkspaceManagedWorktreePullRequestCoordinator {
        var remaining = pullRequests
        return WorkspaceManagedWorktreePullRequestCoordinator(
            model: model,
            inspectBranch: { [self] _, _, _ in branchInspection ?? inspection() },
            inspectPullRequest: inspectPullRequest ?? { _, _ in
                GitHubPullRequestLookup(pullRequest: remaining.removeFirst())
            },
            runTool: runTool
        )
    }
}
