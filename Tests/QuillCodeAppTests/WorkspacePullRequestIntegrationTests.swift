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

    func testWorkspacePullRequestCommandsPrefillComposerOrOpenStructuredDraft() throws {
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
        XCTAssertEqual(model.pullRequestReviewDraft?.action, .approve)
        XCTAssertEqual(model.surface().review.title, "Review pull request")
        XCTAssertTrue(model.surface().review.isVisible)

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-review-comment", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Comment on a pull request line: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-review-reply", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Reply to pull request review comment: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-review-thread", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Resolve pull request review thread: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-labels", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Label the current pull request: ")

        XCTAssertTrue(model.runWorkspaceCommand("git-pr-merge", workspaceRoot: root))
        XCTAssertEqual(model.composer.draft, "Merge the current pull request with squash")
    }

    func testStructuredPullRequestReviewDraftSubmitsGitHubReviewThroughSSH() throws {
        let fixture = try makeRemotePullRequestFixture()

        XCTAssertTrue(fixture.model.runWorkspaceCommand("git-pr-review", workspaceRoot: fixture.localRoot))
        fixture.model.updatePullRequestReviewDraft(WorkspacePullRequestReviewDraftSurface(
            action: .requestChanges,
            selector: "456",
            body: "Please add tests."
        ))

        XCTAssertTrue(fixture.model.submitPullRequestReviewDraft(workspaceRoot: fixture.localRoot))
        let card = try XCTUnwrap(fixture.model.currentToolCards.last)
        XCTAssertEqual(card.title, ToolDefinition.gitPullRequestReview.name)
        XCTAssertEqual(card.executionContext?.kind, .sshRemote)
        XCTAssertNil(fixture.model.pullRequestReviewDraft)
        XCTAssertEqual(try fixture.recordedGHArguments(), [
            "pr", "review", "456", "--request-changes", "--body", "Please add tests."
        ])
    }

    func testStructuredPullRequestReviewDraftSubmitsInlineNotesBeforeReviewThroughSSH() throws {
        let fixture = try makeRemotePullRequestFixture(recordingReviewCalls: true)
        let sources = fixture.remoteRoot.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let appFile = sources.appendingPathComponent("App.swift")
        try "func old() {}\n".write(to: appFile, atomically: true, encoding: .utf8)
        _ = try runGit(["add", "Sources/App.swift"], cwd: fixture.remoteRoot)
        _ = try runGit(["commit", "-m", "add app"], cwd: fixture.remoteRoot)
        try "func old() {}\nfunc newBranch() {}\n".write(to: appFile, atomically: true, encoding: .utf8)

        _ = fixture.model.runToolCall(
            ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}"),
            workspaceRoot: fixture.localRoot
        )
        XCTAssertTrue(fixture.model.addReviewComment(
            path: "Sources/App.swift",
            lineNumber: 2,
            lineKind: .insertion,
            text: "Cover this new branch."
        ))
        XCTAssertTrue(fixture.model.runWorkspaceCommand("git-pr-review", workspaceRoot: fixture.localRoot))
        var draft = try XCTUnwrap(fixture.model.pullRequestReviewDraft)
        XCTAssertEqual(draft.inlineCommentCount, 1)
        draft.inlineComments.append(WorkspacePullRequestReviewDraftCommentSurface(
            path: "Sources/App.swift",
            line: 2,
            body: "Do not post this skipped note.",
            isIncluded: false
        ))
        XCTAssertEqual(draft.inlineCommentCount, 2)
        XCTAssertEqual(draft.selectedInlineCommentCount, 1)
        draft.action = .requestChanges
        draft.selector = "456"
        draft.body = "Please address the inline note."
        fixture.model.updatePullRequestReviewDraft(draft)

        XCTAssertTrue(fixture.model.submitPullRequestReviewDraft(workspaceRoot: fixture.localRoot))

        XCTAssertEqual(fixture.model.currentToolCards.suffix(2).map(\.title), [
            ToolDefinition.gitPullRequestReviewComment.name,
            ToolDefinition.gitPullRequestReview.name
        ])
        XCTAssertNil(fixture.model.pullRequestReviewDraft)
        XCTAssertEqual(try fixture.recordedGitHubCallArguments(), [
            [
                "api",
                "repos/example/repo/pulls/456/comments",
                "--raw-field",
                "body=Cover this new branch.",
                "--raw-field",
                "commit_id=abc123",
                "--raw-field",
                "path=Sources/App.swift",
                "--field",
                "line=2",
                "--raw-field",
                "side=RIGHT"
            ],
            [
                "pr",
                "review",
                "456",
                "--request-changes",
                "--body",
                "Please address the inline note."
            ]
        ])
    }

    private func makeRemotePullRequestFixture(recordingReviewCalls: Bool = false) throws -> RemotePullRequestFixture {
        let localRoot = try makeTempDirectory()
        let bin = localRoot.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ghArgumentsFile = localRoot.appendingPathComponent("gh-args.txt")
        if recordingReviewCalls {
            _ = try makeRecordingReviewFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        } else {
            _ = try makeFakeGitHubCLI(in: bin, argumentsFile: ghArgumentsFile)
        }
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
            remoteRoot: remoteRoot,
            model: model
        )
    }

    private func makeRecordingReviewFakeGitHubCLI(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("gh")
        let argumentsPath = shellSingleQuotedForPullRequestTest(argumentsFile.path)
        try """
        #!/bin/sh
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
          if [ "$7" = '.number + " " + .headRefOid' ]; then
            echo '456 abc123'
          else
            echo '{"number":456,"headRefOid":"abc123"}'
          fi
        elif [ "$1" = "repo" ] && [ "$2" = "view" ]; then
          if [ "$6" = ".nameWithOwner" ]; then
            echo 'example/repo'
          else
            echo '{"nameWithOwner":"example/repo"}'
          fi
        elif [ "$1" = "api" ]; then
          printf '%s\\n' __CALL__ >> '\(argumentsPath)'
          printf '%s\\n' "$@" >> '\(argumentsPath)'
          echo '{"html_url":"https://github.com/example/repo/pull/456#discussion_r99"}'
        elif [ "$1" = "pr" ] && [ "$2" = "review" ]; then
          printf '%s\\n' __CALL__ >> '\(argumentsPath)'
          printf '%s\\n' "$@" >> '\(argumentsPath)'
          echo 'https://github.com/example/repo/pull/456'
        else
          printf '%s\\n' "$@" >&2
          exit 1
        fi
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func shellSingleQuotedForPullRequestTest(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }
}

private struct RemotePullRequestFixture {
    var localRoot: URL
    var ghArgumentsFile: URL
    var remoteRoot: URL
    var model: QuillCodeWorkspaceModel

    func recordedGHArguments() throws -> [String] {
        try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    func recordedGitHubCallArguments() throws -> [[String]] {
        try String(contentsOf: ghArgumentsFile, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .split(separator: "__CALL__")
            .map { Array($0) }
    }
}
