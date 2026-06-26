import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspacePullRequestIntegrationTests: XCTestCase {
    func testRemoteWorkspaceCommandsViewPullRequestAndChecksThroughSSH() throws {
        let fixture = try makeRemotePullRequestFixture()

        XCTAssertTrue(fixture.model.runWorkspaceCommand("git-pr-view", workspaceRoot: fixture.localRoot))
        var card = try XCTUnwrap(fixture.model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(card.artifacts.map(\.value), ["https://github.com/example/repo/pull/456"])
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "view", "--comments"])

        XCTAssertTrue(fixture.model.runWorkspaceCommand("git-pr-checks", workspaceRoot: fixture.localRoot))
        card = try XCTUnwrap(fixture.model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "checks"])

        XCTAssertTrue(fixture.model.runWorkspaceCommand("git-pr-diff", workspaceRoot: fixture.localRoot))
        card = try XCTUnwrap(fixture.model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertEqual(card.status, .done)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "diff"])

        XCTAssertTrue(fixture.model.runWorkspaceCommand("git-pr-checkout", workspaceRoot: fixture.localRoot))
        XCTAssertEqual(fixture.model.composer.draft, "Checkout pull request ")
    }

    func testPullRequestSlashCommandsDispatchStructuredGitHubToolsThroughSSH() async throws {
        let fixture = try makeRemotePullRequestFixture()

        fixture.model.setDraft("/pr view 456")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(fixture.model.currentToolCards.last?.executionContext?.kind, .sshRemote)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "view", "456", "--comments"])

        fixture.model.setDraft("/pr checks 456")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestChecks.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "checks", "456"])

        fixture.model.setDraft("/pr diff 456")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestDiff.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "diff", "456"])

        fixture.model.setDraft("/pr checkout 456")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestCheckout.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "checkout", "456"])

        fixture.model.setDraft("/pr comment 456 ship it")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestComment.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "comment", "456", "--body", "ship it"])

        fixture.model.setDraft("/pr review approve 456")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReview.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "review", "456", "--approve"])

        fixture.model.setDraft("/pr reviewers add alice bob")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestReviewers.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "edit", "--add-reviewer", "alice,bob"])

        fixture.model.setDraft("/pr labels add 456 merge-train, needs review")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "edit", "456", "--add-label", "merge-train,needs review"])

        fixture.model.setDraft("/pr labels remove stale")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestLabels.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "edit", "--remove-label", "stale"])

        fixture.model.setDraft("/pr merge 456 rebase auto delete-branch")
        await fixture.model.submitComposer(workspaceRoot: fixture.localRoot)
        XCTAssertEqual(fixture.model.currentToolCards.last?.title, ToolDefinition.gitPullRequestMerge.name)
        XCTAssertEqual(try fixture.recordedGHArguments(), ["pr", "merge", "456", "--rebase", "--auto", "--delete-branch"])
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

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-review-comment", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Comment on a pull request line: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-labels", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Label the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-merge", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Merge the current pull request with squash")
    }

    private func makeRemotePullRequestFixture() throws -> RemotePullRequestFixture {
        let localRoot = try makeTempDirectory()
        let bin = localRoot.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = localRoot.appendingPathComponent("gh-args.txt")
        _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        let sshArgumentsFile = localRoot.appendingPathComponent("ssh-args.txt")
        let fakeSSH = try makeExecutingFakeSSH(
            in: localRoot,
            argumentsFile: sshArgumentsFile,
            pathPrefix: bin
        )
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
        return RemotePullRequestFixture(
            localRoot: localRoot,
            ghArgumentsFile: ghArgumentsFile,
            model: model
        )
    }
}

private struct RemotePullRequestFixture {
    var localRoot: URL
    var ghArgumentsFile: URL
    var model: QuillCodeWorkspaceModel

    func recordedGHArguments() throws -> [String] {
        try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }
}
