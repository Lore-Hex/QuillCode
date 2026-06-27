import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class GitToolRouterTests: XCTestCase {
    func testToolRouterExposesGitDefinitions() {
        let definitions = ToolRouter.definitions.map(\.name)

        XCTAssertEqual(definitions.first, "host.shell.run")
        XCTAssertTrue(definitions.contains("host.shell.run"))
        XCTAssertTrue(definitions.contains("host.git.stage"))
        XCTAssertTrue(definitions.contains("host.git.restore"))
        XCTAssertTrue(definitions.contains("host.git.stage_hunk"))
        XCTAssertTrue(definitions.contains("host.git.restore_hunk"))
        XCTAssertTrue(definitions.contains("host.git.commit"))
        XCTAssertTrue(definitions.contains("host.git.push"))
        XCTAssertTrue(definitions.contains("host.git.pr.create"))
        XCTAssertTrue(definitions.contains("host.git.pr.view"))
        XCTAssertTrue(definitions.contains("host.git.pr.checks"))
        XCTAssertTrue(definitions.contains("host.git.pr.diff"))
        XCTAssertTrue(definitions.contains("host.git.pr.checkout"))
        XCTAssertTrue(definitions.contains("host.git.pr.reviewers"))
        XCTAssertTrue(definitions.contains("host.git.pr.labels"))
        XCTAssertTrue(definitions.contains("host.git.pr.comment"))
        XCTAssertTrue(definitions.contains("host.git.pr.review"))
        XCTAssertTrue(definitions.contains("host.git.pr.review_comment"))
        XCTAssertTrue(definitions.contains("host.git.pr.review_reply"))
        XCTAssertTrue(definitions.contains("host.git.pr.review_threads"))
        XCTAssertTrue(definitions.contains("host.git.pr.review_thread"))
        XCTAssertTrue(definitions.contains("host.git.pr.merge"))
        XCTAssertTrue(definitions.contains("host.git.worktree.list"))
        XCTAssertTrue(definitions.contains("host.git.worktree.create"))
        XCTAssertTrue(definitions.contains("host.git.worktree.open"))
        XCTAssertTrue(definitions.contains("host.git.worktree.remove"))
        XCTAssertTrue(definitions.contains("host.git.worktree.prune"))
    }

    func testGitToolCallDispatcherOwnsGitDefinitions() {
        let routerDefinitions = ToolRouter.definitions.map(\.name)
        let gitDefinitions = GitToolCallDispatcher.definitions.map(\.name)

        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitStatus.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitPullRequestCreate.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitWorktreeOpen.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitWorktreeRemove.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitWorktreePrune.name))
        XCTAssertFalse(GitToolCallDispatcher.handles(ToolDefinition.shellRun.name))
        XCTAssertTrue(gitDefinitions.allSatisfy(routerDefinitions.contains))
    }

    func testToolRouterRoutesGitWorktreeList() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.gitWorktreeList.name,
            argumentsJSON: "{}"
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(result.stdout.contains(root.path), result.stdout)
    }

    func testToolRouterRoutesGitWorktreePrune() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.gitWorktreePrune.name,
            argumentsJSON: #"{"dryRun":true,"verbose":true}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }

    func testToolRouterRoutesGitPush() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        let remote = parent.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init --bare '\(remote.path)'", cwd: parent)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git remote add origin '\(remote.path)'", cwd: root)).ok)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "Add hello").ok)

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.gitPush.name,
            argumentsJSON: #"{"remote":"origin","setUpstream":true}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }
}
