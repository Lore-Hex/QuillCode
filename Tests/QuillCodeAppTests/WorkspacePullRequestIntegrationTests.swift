import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspacePullRequestIntegrationTests: XCTestCase {
    func testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH() throws {
        let root = try makeTempDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let sshArgumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let connection = ProjectConnection.ssh(
            path: remoteRoot.path,
            host: "feather.local",
            user: "quill",
            port: 2222
        )
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-view", workspaceRoot: root))
        var card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.artifacts.map(\.value), ["https://github.com/example/repo/pull/456"])
        var ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "view", "--comments"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checks", workspaceRoot: root))
        card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "checks"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-diff", workspaceRoot: root))
        card = try XCTUnwrap(model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        ghArguments = try String(contentsOf: ghArgumentsFile, encoding: .utf8)
        XCTAssertEqual(ghArguments.split(separator: "\n").map(String.init), ["pr", "diff"])

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checkout", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Checkout pull request ")
    }

    func testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH() async throws {
        let root = try makeTempDirectory()
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = root.appendingPathComponent("gh-args.txt")
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let sshArgumentsFile = root.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(in: root, argumentsFile: sshArgumentsFile, pathPrefix: bin)
        let remoteRoot = try makeTempGitRepoWithInitialCommit()
        let connection = ProjectConnection.ssh(path: remoteRoot.path, host: "feather.local", user: "quill")
        let project = ProjectRef(name: "Feather", path: connection.path, connection: connection)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(projects: [project], selectedProjectID: project.id),
            sshRemoteShellExecutor: SSHRemoteShellExecutor(
                sshExecutable: fakeSSH.path,
                connectTimeoutSeconds: 4
            )
        )

        func ghArguments() throws -> [String] {
            try String(contentsOf: ghArgumentsFile, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
        }

        model.setDraft("/pr view 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(model.currentToolCards.last?.executionContext?.kind, .sshRemote)
        XCTAssertEqual(try ghArguments(), ["pr", "view", "456", "--comments"])

        model.setDraft("/pr checks 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(try ghArguments(), ["pr", "checks", "456"])

        model.setDraft("/pr diff 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(try ghArguments(), ["pr", "diff", "456"])

        model.setDraft("/pr checkout 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestCheckout.name)
        XCTAssertEqual(try ghArguments(), ["pr", "checkout", "456"])

        model.setDraft("/pr comment 456 ship it")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestComment.name)
        XCTAssertEqual(try ghArguments(), ["pr", "comment", "456", "--body", "ship it"])

        model.setDraft("/pr review approve 456")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReview.name)
        XCTAssertEqual(try ghArguments(), ["pr", "review", "456", "--approve"])

        model.setDraft("/pr reviewers add alice bob")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReviewers.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "--add-reviewer", "alice,bob"])

        model.setDraft("/pr labels add 456 merge-train, needs review")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "456", "--add-label", "merge-train,needs review"])

        model.setDraft("/pr labels remove stale")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try ghArguments(), ["pr", "edit", "--remove-label", "stale"])

        model.setDraft("/pr merge 456 rebase auto delete-branch")
        await model.submitComposer(workspaceRoot: root)
        XCTAssertEqual(model.currentToolCards.last?.title, ToolDefinition.gitPullRequestMerge.name)
        XCTAssertEqual(try ghArguments(), ["pr", "merge", "456", "--rebase", "--auto", "--delete-branch"])
    }

    func testWorkspacePullRequestCommandsPrefillComposer() throws {
        let root = try makeTempDirectory()
        let model = QuillCodeWorkspaceModel()

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-create", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Create a pull request titled ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-checkout", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Checkout pull request ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-reviewers", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Request reviewers for the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-comment", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Comment on the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-review", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Review the current pull request: approve")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-labels", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Label the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-merge", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Merge the current pull request with squash")
    }
}
