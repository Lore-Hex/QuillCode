import Foundation
import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceManagedWorktreePublishCoordinatorTests: XCTestCase {
    func testFirstPublishPushesWithUpstreamThenCreatesPullRequest() throws {
        let fixture = try makeFixture()
        var calls: [ToolCall] = []
        let coordinator = WorkspaceManagedWorktreePublishCoordinator(
            model: fixture.model,
            inspect: { _, branch, base in
                GitBranchPublicationInspection(
                    branch: branch,
                    baseBranch: base,
                    headCommit: "abc123",
                    hasUncommittedChanges: false,
                    commitsAheadOfBase: 2,
                    upstream: nil
                )
            },
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true, stdout: call.name == ToolDefinition.gitPullRequestCreate.name
                    ? "Created https://github.com/Lore-Hex/QuillCode/pull/42#discussion\n"
                    : "")
            }
        )

        XCTAssertTrue(coordinator.publishSelectedThread())
        XCTAssertEqual(calls.map(\.name), [
            ToolDefinition.gitPush.name,
            ToolDefinition.gitPullRequestCreate.name
        ])
        let push = try ToolArguments(XCTUnwrap(calls.first?.argumentsJSON))
        XCTAssertEqual(push.string("branch"), fixture.branch)
        XCTAssertEqual(push.string("remote"), "origin")
        XCTAssertEqual(push.bool("setUpstream"), true)
        let create = try ToolArguments(XCTUnwrap(calls.last?.argumentsJSON))
        XCTAssertEqual(create.string("head"), fixture.branch)
        XCTAssertEqual(create.string("base"), "main")
        XCTAssertEqual(create.bool("fill"), true)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.number, 42)
        XCTAssertEqual(
            fixture.model.selectedThread?.pullRequest?.url,
            "https://github.com/Lore-Hex/QuillCode/pull/42"
        )
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.headCommit, "abc123")
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.status, .open)
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("opened its pull request") == true)
    }

    func testExistingPullRequestIsRefreshedWithoutRedundantPush() throws {
        let fixture = try makeFixture()
        var calls: [ToolCall] = []
        let coordinator = WorkspaceManagedWorktreePublishCoordinator(
            model: fixture.model,
            inspect: { _, branch, base in
                GitBranchPublicationInspection(
                    branch: branch,
                    baseBranch: base,
                    headCommit: "abc123",
                    hasUncommittedChanges: false,
                    commitsAheadOfBase: 3,
                    upstream: "origin/\(branch)",
                    pullRequest: GitBranchPublicationPullRequest(
                        number: 42,
                        title: "Publish branch",
                        url: "https://github.com/Lore-Hex/QuillCode/pull/42",
                        state: "OPEN",
                        isDraft: false,
                        baseBranch: "main",
                        headBranch: branch
                    )
                )
            },
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertTrue(coordinator.publishSelectedThread())
        XCTAssertEqual(calls.map(\.name), [ToolDefinition.gitPullRequestView.name])
        let view = try ToolArguments(XCTUnwrap(calls.first?.argumentsJSON))
        XCTAssertEqual(view.string("selector"), "42")
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.number, 42)
        XCTAssertEqual(fixture.model.selectedThread?.pullRequest?.headCommit, "abc123")
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("#42") == true)
    }

    func testDirtyBranchShowsStatusAndDoesNotPublish() throws {
        let fixture = try makeFixture()
        var calls: [ToolCall] = []
        let coordinator = WorkspaceManagedWorktreePublishCoordinator(
            model: fixture.model,
            inspect: { _, branch, base in
                GitBranchPublicationInspection(
                    branch: branch,
                    baseBranch: base,
                    hasUncommittedChanges: true,
                    commitsAheadOfBase: 1,
                    upstream: nil
                )
            },
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertFalse(coordinator.publishSelectedThread())
        XCTAssertEqual(calls.map(\.name), [ToolDefinition.gitStatus.name])
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("Nothing was pushed") == true)
    }

    func testBehindUpstreamStopsBeforeMutation() throws {
        let fixture = try makeFixture()
        var calls: [ToolCall] = []
        let coordinator = WorkspaceManagedWorktreePublishCoordinator(
            model: fixture.model,
            inspect: { _, branch, base in
                GitBranchPublicationInspection(
                    branch: branch,
                    baseBranch: base,
                    hasUncommittedChanges: false,
                    commitsAheadOfBase: 2,
                    upstream: "origin/\(branch)",
                    commitsAheadOfUpstream: 1,
                    commitsBehindUpstream: 1
                )
            },
            runTool: { call, _, _ in
                calls.append(call)
                return ToolResult(ok: true)
            }
        )

        XCTAssertFalse(coordinator.publishSelectedThread())
        XCTAssertEqual(calls, [])
        XCTAssertTrue(fixture.model.selectedThread?.events.last?.summary.contains("behind its upstream") == true)
    }

    private func makeFixture() throws -> Fixture {
        let worktree = try makeTempDirectory()
        let branch = "feature/publish"
        let project = ProjectRef(name: "QuillCode", path: worktree.deletingLastPathComponent().path)
        var thread = ChatThread(title: "Publish", projectID: project.id)
        thread.worktree = WorktreeBinding(
            path: worktree.path,
            branch: branch,
            base: "main",
            location: .worktree
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))
        return Fixture(model: model, branch: branch)
    }
}

private struct Fixture {
    var model: QuillCodeWorkspaceModel
    var branch: String
}
