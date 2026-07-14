import Foundation
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
        XCTAssertTrue(definitions.contains("host.git.fetch"))
        XCTAssertTrue(definitions.contains("host.git.pull"))
        XCTAssertTrue(definitions.contains("host.git.stage_hunk"))
        XCTAssertTrue(definitions.contains("host.git.unstage_hunk"))
        XCTAssertTrue(definitions.contains("host.git.restore_hunk"))
        XCTAssertTrue(definitions.contains("host.git.branch.list"))
        XCTAssertTrue(definitions.contains("host.git.branch.switch"))
        XCTAssertTrue(definitions.contains("host.git.commit"))
        XCTAssertTrue(definitions.contains("host.git.push"))
        XCTAssertTrue(definitions.contains("host.git.pr.list"))
        XCTAssertTrue(definitions.contains("host.git.pr.create"))
        XCTAssertTrue(definitions.contains("host.git.pr.view"))
        XCTAssertTrue(definitions.contains("host.git.pr.checks"))
        XCTAssertTrue(definitions.contains("host.git.pr.diff"))
        XCTAssertTrue(definitions.contains("host.git.pr.checkout"))
        XCTAssertTrue(definitions.contains("host.git.pr.reviewers"))
        XCTAssertTrue(definitions.contains("host.git.pr.labels"))
        XCTAssertTrue(definitions.contains("host.git.pr.comment"))
        XCTAssertTrue(definitions.contains("host.git.pr.lifecycle"))
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
        XCTAssertTrue(definitions.contains("host.git.worktree.create_branch"))
    }

    func testGitToolCallDispatcherOwnsGitDefinitions() {
        let routerDefinitions = ToolRouter.definitions.map(\.name)
        let gitDefinitions = GitToolCallDispatcher.definitions.map(\.name)

        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitStatus.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitBranchList.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitBranchSwitch.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitPullRequestList.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitPullRequestCreate.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitWorktreeOpen.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitWorktreeRemove.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(ToolDefinition.gitWorktreePrune.name))
        XCTAssertFalse(GitToolCallDispatcher.handles(ToolDefinition.shellRun.name))
        XCTAssertTrue(gitDefinitions.allSatisfy(routerDefinitions.contains))
    }

    func testGitWorktreeHandoffDefinitionAndDispatcherOwnership() throws {
        let definition = ToolDefinition.gitWorktreeHandoff
        let routerDefinitions = ToolRouter.definitions.map(\.name)
        let dispatcherDefinitions = GitToolCallDispatcher.definitions.map(\.name)

        XCTAssertEqual(definition.name, "host.git.worktree.handoff")
        XCTAssertEqual(definition.risk, .destructive)
        XCTAssertTrue(routerDefinitions.contains(definition.name))
        XCTAssertTrue(dispatcherDefinitions.contains(definition.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(definition.name))

        let schema = try schemaDictionary(for: definition)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let destination = try XCTUnwrap(properties["destination"] as? [String: Any])
        XCTAssertEqual(destination["type"] as? String, "string")
        XCTAssertEqual(schema["required"] as? [String], ["destination"])
    }

    func testGitWorktreeCreateBranchDefinitionAndDispatcherOwnership() throws {
        let definition = ToolDefinition.gitWorktreeCreateBranch

        XCTAssertEqual(definition.name, "host.git.worktree.create_branch")
        XCTAssertEqual(definition.risk, .append)
        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(definition.name))
        XCTAssertTrue(GitToolCallDispatcher.handles(definition.name))

        let schema = try schemaDictionary(for: definition)
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual((properties["branch"] as? [String: Any])?["type"] as? String, "string")
        XCTAssertEqual(schema["required"] as? [String], ["branch"])
    }

    func testGitToolDefinitionsExposeValidObjectSchemas() throws {
        for definition in GitToolCallDispatcher.definitions {
            let schema = try schemaDictionary(for: definition)
            XCTAssertEqual(schema["type"] as? String, "object", definition.name)
            XCTAssertNotNil(schema["properties"] as? [String: Any], definition.name)
        }

        let reviewSchema = try schemaDictionary(for: .gitPullRequestReview)
        let reviewProperties = try XCTUnwrap(reviewSchema["properties"] as? [String: Any])
        let reviewAction = try XCTUnwrap(reviewProperties["action"] as? [String: Any])
        XCTAssertEqual(reviewAction["enum"] as? [String], ["approve", "comment", "request_changes"])

        let reviewersSchema = try schemaDictionary(for: .gitPullRequestReviewers)
        let reviewersProperties = try XCTUnwrap(reviewersSchema["properties"] as? [String: Any])
        let addReviewers = try XCTUnwrap(reviewersProperties["add"] as? [String: Any])
        let reviewerItems = try XCTUnwrap(addReviewers["items"] as? [String: Any])
        XCTAssertEqual(addReviewers["type"] as? String, "array")
        XCTAssertEqual(reviewerItems["type"] as? String, "string")

        let lifecycleSchema = try schemaDictionary(for: .gitPullRequestLifecycle)
        let lifecycleProperties = try XCTUnwrap(lifecycleSchema["properties"] as? [String: Any])
        let lifecycleAction = try XCTUnwrap(lifecycleProperties["action"] as? [String: Any])
        XCTAssertEqual(lifecycleAction["enum"] as? [String], ["close", "reopen"])
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

    func testToolRouterRoutesGitWorktreeHandoff() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let worktreeName = "router-handoff-\(UUID().uuidString)"
        let worktree = root.deletingLastPathComponent().appendingPathComponent(worktreeName)
        let git = GitToolExecutor()
        let create = git.createWorktree(cwd: root, path: worktreeName, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        defer { _ = git.removeWorktree(cwd: root, path: worktreeName, force: true) }
        try "routed\n".write(
            to: root.appendingPathComponent("routed.txt"),
            atomically: true,
            encoding: .utf8
        )

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.gitWorktreeHandoff.name,
            argumentsJSON: #"{"destination":"\#(worktreeName)"}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, [worktree.path])
        XCTAssertEqual(try String(contentsOf: worktree.appendingPathComponent("routed.txt")), "routed\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("routed.txt").path))
    }

    func testToolRouterRoutesGitWorktreeCreateBranch() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let name = "router-branch-here-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let git = GitToolExecutor()
        let create = git.createWorktree(cwd: root, path: name, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        defer { _ = git.removeWorktree(cwd: root, path: name, force: true) }

        let result = ToolRouter(workspaceRoot: target).execute(ToolCall(
            name: ToolDefinition.gitWorktreeCreateBranch.name,
            argumentsJSON: #"{"branch":"feature/router-owned"}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["feature/router-owned"])
        XCTAssertEqual(currentBranchName(in: target), "feature/router-owned")
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

    func testToolRouterRoutesGitBranchSwitch() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.gitBranchSwitch.name,
            argumentsJSON: #"{"branch":"feature/router","create":true,"startPoint":"HEAD"}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(currentBranchName(in: root), "feature/router")
    }

    private func schemaDictionary(for definition: ToolDefinition) throws -> [String: Any] {
        let data = try XCTUnwrap(definition.parametersJSON.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(json as? [String: Any])
    }
}
