import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class GitHubPullRequestToolExecutorTests: XCTestCase {
    func testCreatePullRequestUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.createPullRequest(
            cwd: fixture.root,
            title: "Add PR tool",
            body: "Adds structured pull request creation.",
            base: "main",
            head: "feature/pr-tool",
            draft: true
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        XCTAssertEqual(try fixture.arguments(), [
            "pr",
            "create",
            "--title",
            "Add PR tool",
            "--body",
            "Adds structured pull request creation.",
            "--base",
            "main",
            "--head",
            "feature/pr-tool",
            "--draft"
        ])
    }

    func testCreatePullRequestRequiresTitleUnlessFillIsEnabled() throws {
        let fixture = try makeFixture()

        XCTAssertFalse(fixture.git.createPullRequest(cwd: fixture.root, title: " ").ok)

        let result = fixture.git.createPullRequest(cwd: fixture.root, fill: true)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "create", "--fill"])
    }

    func testViewPullRequestUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.viewPullRequest(cwd: fixture.root, selector: "123")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        XCTAssertEqual(try fixture.arguments(), ["pr", "view", "123", "--comments"])
    }

    func testPullRequestChecksUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.pullRequestChecks(cwd: fixture.root, selector: "https://github.com/example/repo/pull/123")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "checks", "https://github.com/example/repo/pull/123"])
    }

    func testPullRequestDiffUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.diffPullRequest(cwd: fixture.root, selector: "123")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "diff", "123"])
    }

    func testPullRequestCheckoutUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.checkoutPullRequest(cwd: fixture.root, selector: "123", branch: "review/pr-123")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "checkout", "123", "--branch", "review/pr-123"])
    }

    func testPullRequestReviewersUseGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.updatePullRequestReviewers(
            cwd: fixture.root,
            selector: "123",
            add: ["alice", "myorg/platform-team", "alice"],
            remove: ["bob"]
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        XCTAssertEqual(try fixture.arguments(), [
            "pr",
            "edit",
            "123",
            "--add-reviewer",
            "alice,myorg/platform-team",
            "--remove-reviewer",
            "bob"
        ])
    }

    func testPullRequestReviewersRequireReviewerAndValidateNames() throws {
        let fixture = try makeFixture()

        XCTAssertFalse(fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123").ok)
        XCTAssertFalse(fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123", add: ["bad reviewer"]).ok)
        XCTAssertFalse(fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123", add: ["-bad"]).ok)
        XCTAssertFalse(fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123", add: ["org/team/extra"]).ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsFile.path))
    }

    func testPullRequestLabelsUseGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.updatePullRequestLabels(
            cwd: fixture.root,
            selector: "123",
            add: ["merge-train", "needs review", "merge-train"],
            remove: ["blocked"]
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        XCTAssertEqual(try fixture.arguments(), [
            "pr",
            "edit",
            "123",
            "--add-label",
            "merge-train,needs review",
            "--remove-label",
            "blocked"
        ])
    }

    func testPullRequestLabelsRequireLabelAndValidateNames() throws {
        let fixture = try makeFixture()

        XCTAssertFalse(fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123").ok)
        XCTAssertFalse(fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123", add: ["-bad"]).ok)
        XCTAssertFalse(fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123", add: ["bad,label"]).ok)
        XCTAssertFalse(fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123", add: ["bad\nlabel"]).ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsFile.path))
    }

    func testPullRequestCommentUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.commentOnPullRequest(cwd: fixture.root, selector: "123", body: "Ready for review.")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        XCTAssertEqual(try fixture.arguments(), ["pr", "comment", "123", "--body", "Ready for review."])
    }

    func testPullRequestCommentRequiresBody() throws {
        let fixture = try makeFixture()

        let result = fixture.git.commentOnPullRequest(cwd: fixture.root, selector: "123", body: " ")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("comment body is required") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsFile.path))
    }

    func testPullRequestReviewUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.reviewPullRequest(
            cwd: fixture.root,
            selector: "123",
            action: "request_changes",
            body: "Please add tests."
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        XCTAssertEqual(try fixture.arguments(), ["pr", "review", "123", "--request-changes", "--body", "Please add tests."])
    }

    func testPullRequestReviewAllowsApprovalWithoutBody() throws {
        let fixture = try makeFixture()

        let result = fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123", action: "approve")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "review", "123", "--approve"])
    }

    func testPullRequestReviewRequiresValidActionAndBodyWhenNeeded() throws {
        let fixture = try makeFixture()

        XCTAssertFalse(fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123", action: "merge", body: "ok").ok)
        XCTAssertFalse(fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123", action: "comment", body: " ").ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsFile.path))
    }

    func testPullRequestReviewCommentUsesGitHubAPIArguments() throws {
        let fixture = try makeReviewCommentFixture()

        let result = fixture.git.commentOnPullRequestLine(
            cwd: fixture.root,
            selector: "123",
            path: "Sources/App.swift",
            line: 42,
            side: "right",
            body: "Check this edge case.",
            startLine: 40
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123#discussion_r99"])
        XCTAssertEqual(try fixture.arguments(), [
            "api",
            "repos/example/repo/pulls/123/comments",
            "--raw-field",
            "body=Check this edge case.",
            "--raw-field",
            "commit_id=abc123",
            "--raw-field",
            "path=Sources/App.swift",
            "--field",
            "line=42",
            "--raw-field",
            "side=RIGHT",
            "--field",
            "start_line=40",
            "--raw-field",
            "start_side=RIGHT"
        ])
    }

    func testPullRequestReviewCommentValidatesInputsBeforeGitHubCalls() throws {
        let fixture = try makeReviewCommentFixture()

        XCTAssertFalse(fixture.git.commentOnPullRequestLine(cwd: fixture.root, path: "../App.swift", line: 42, body: "Comment").ok)
        XCTAssertFalse(fixture.git.commentOnPullRequestLine(cwd: fixture.root, path: "App.swift", line: 0, body: "Comment").ok)
        XCTAssertFalse(fixture.git.commentOnPullRequestLine(cwd: fixture.root, path: "App.swift", line: 42, side: "BOTH", body: "Comment").ok)
        XCTAssertFalse(fixture.git.commentOnPullRequestLine(cwd: fixture.root, path: "App.swift", line: 42, body: " ", startLine: 40).ok)
        XCTAssertFalse(fixture.git.commentOnPullRequestLine(cwd: fixture.root, path: "App.swift", line: 42, body: "Comment", startLine: 50).ok)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.argumentsFile.path))
    }

    func testPullRequestMergeUsesGitHubCLIArguments() throws {
        let fixture = try makeFixture()

        let result = fixture.git.mergePullRequest(
            cwd: fixture.root,
            selector: "123",
            method: "rebase",
            auto: true,
            deleteBranch: true
        )

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        XCTAssertEqual(try fixture.arguments(), ["pr", "merge", "123", "--rebase", "--auto", "--delete-branch"])
    }

    func testPullRequestMergeDefaultsToSquashAndRejectsInvalidMethod() throws {
        let fixture = try makeFixture()

        let result = fixture.git.mergePullRequest(cwd: fixture.root, selector: "123")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "merge", "123", "--squash"])

        XCTAssertFalse(fixture.git.mergePullRequest(cwd: fixture.root, selector: "123", method: "octopus").ok)
        XCTAssertEqual(try fixture.arguments(), ["pr", "merge", "123", "--squash"])
    }

    func testPullRequestToolsRejectUnsafeSelector() throws {
        let fixture = try makeFixture()

        XCTAssertFalse(fixture.git.viewPullRequest(cwd: fixture.root, selector: "--json").ok)
        XCTAssertFalse(fixture.git.pullRequestChecks(cwd: fixture.root, selector: "feature branch").ok)
        XCTAssertFalse(fixture.git.diffPullRequest(cwd: fixture.root, selector: "--patch").ok)
        XCTAssertFalse(fixture.git.checkoutPullRequest(cwd: fixture.root, selector: "123 --web").ok)
        XCTAssertFalse(fixture.git.checkoutPullRequest(cwd: fixture.root, selector: "123", branch: "--bad").ok)
        XCTAssertFalse(fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123 --web", add: ["alice"]).ok)
        XCTAssertFalse(fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123 --web", add: ["merge-train"]).ok)
        XCTAssertFalse(fixture.git.commentOnPullRequest(cwd: fixture.root, selector: "123 --web", body: "Comment").ok)
        XCTAssertFalse(fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123 --web", action: "approve").ok)
        XCTAssertFalse(fixture.git.mergePullRequest(cwd: fixture.root, selector: "123 --web").ok)
        XCTAssertThrowsError(try GitToolExecutor.safePullRequestSelector("--web"))
    }

    func testPullRequestHelpersNormalizeInputsAndExtractURLs() throws {
        XCTAssertNil(try GitHubPullRequestInputValidator.safeSelector(" \n "))
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeSelector("  123  "), "123")
        XCTAssertEqual(
            try GitHubPullRequestInputValidator.safeReviewers(["alice", "alice", "org/team", "@copilot"]),
            ["alice", "org/team", "@copilot"]
        )
        XCTAssertEqual(
            try GitHubPullRequestInputValidator.safeLabels(["merge-train", "bug", "merge-train"]),
            ["merge-train", "bug"]
        )
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeReviewFlag("request-change"), "--request-changes")
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeReviewLine(12), 12)
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeReviewSide("left"), "LEFT")
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeMergeFlag(nil), "--squash")
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeMergeFlag("merge-commit"), "--merge")
        XCTAssertEqual(
            GitHubPullRequestOutputParser.extractURLs(from: #"created https://github.com/example/repo/pull/12 ok {"html_url":"https://github.com/example/repo/pull/12#discussion_r1"}"#),
            [
                "https://github.com/example/repo/pull/12",
                "https://github.com/example/repo/pull/12#discussion_r1"
            ]
        )
        XCTAssertEqual(
            GitHubPullRequestOutputParser.extractURLs(from: "created https://github.com/example/repo/pull/12 ok"),
            ["https://github.com/example/repo/pull/12"]
        )

        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeSelector("--json"))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeReviewer("bad user"))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeLabel("bad,label"))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeReviewFlag("ship-it"))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeReviewLine(0))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeReviewSide("both"))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeMergeFlag("octopus"))
    }

    func testToolRouterRoutesPullRequestCreate() throws {
        let fixture = try makeFixture()
        let router = fixture.router()

        let result = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestCreate.name,
            argumentsJSON: #"{"title":"Add PR route","base":"main","draft":true}"#
        ))

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "create", "--title", "Add PR route", "--base", "main", "--draft"])
    }

    func testToolRouterRoutesPullRequestReadAndMutationTools() throws {
        let fixture = try makeFixture()
        let router = fixture.router()

        let view = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestView.name,
            argumentsJSON: #"{"selector":"123"}"#
        ))
        XCTAssertTrue(view.ok, "\(view.error ?? "") \(view.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "view", "123", "--comments"])

        let checks = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestChecks.name,
            argumentsJSON: #"{"selector":"123"}"#
        ))
        XCTAssertTrue(checks.ok, "\(checks.error ?? "") \(checks.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "checks", "123"])

        let diff = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestDiff.name,
            argumentsJSON: #"{"selector":"123"}"#
        ))
        XCTAssertTrue(diff.ok, "\(diff.error ?? "") \(diff.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "diff", "123"])

        let checkout = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestCheckout.name,
            argumentsJSON: #"{"selector":"123","branch":"review/pr-123"}"#
        ))
        XCTAssertTrue(checkout.ok, "\(checkout.error ?? "") \(checkout.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "checkout", "123", "--branch", "review/pr-123"])

        let reviewers = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestReviewers.name,
            argumentsJSON: #"{"selector":"123","add":["alice","myorg/team-name"],"remove":"bob"}"#
        ))
        XCTAssertTrue(reviewers.ok, "\(reviewers.error ?? "") \(reviewers.stderr)")
        XCTAssertEqual(try fixture.arguments(), [
            "pr",
            "edit",
            "123",
            "--add-reviewer",
            "alice,myorg/team-name",
            "--remove-reviewer",
            "bob"
        ])

        let labels = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestLabels.name,
            argumentsJSON: #"{"selector":"123","add":["merge-train","needs review"],"remove":"blocked"}"#
        ))
        XCTAssertTrue(labels.ok, "\(labels.error ?? "") \(labels.stderr)")
        XCTAssertEqual(try fixture.arguments(), [
            "pr",
            "edit",
            "123",
            "--add-label",
            "merge-train,needs review",
            "--remove-label",
            "blocked"
        ])

        let comment = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestComment.name,
            argumentsJSON: #"{"selector":"123","body":"Ready for review."}"#
        ))
        XCTAssertTrue(comment.ok, "\(comment.error ?? "") \(comment.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "comment", "123", "--body", "Ready for review."])

        let review = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestReview.name,
            argumentsJSON: #"{"selector":"123","action":"approve"}"#
        ))
        XCTAssertTrue(review.ok, "\(review.error ?? "") \(review.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "review", "123", "--approve"])

        let reviewCommentFixture = try makeReviewCommentFixture()
        let reviewComment = reviewCommentFixture.router().execute(ToolCall(
            name: ToolDefinition.gitPullRequestReviewComment.name,
            argumentsJSON: #"{"selector":"123","path":"Sources/App.swift","line":42,"body":"Looks good."}"#
        ))
        XCTAssertTrue(reviewComment.ok, "\(reviewComment.error ?? "") \(reviewComment.stderr)")
        XCTAssertEqual(try reviewCommentFixture.arguments(), [
            "api",
            "repos/example/repo/pulls/123/comments",
            "--raw-field",
            "body=Looks good.",
            "--raw-field",
            "commit_id=abc123",
            "--raw-field",
            "path=Sources/App.swift",
            "--field",
            "line=42",
            "--raw-field",
            "side=RIGHT"
        ])

        let merge = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestMerge.name,
            argumentsJSON: #"{"selector":"123","method":"squash","auto":"true","deleteBranch":true}"#
        ))
        XCTAssertTrue(merge.ok, "\(merge.error ?? "") \(merge.stderr)")
        XCTAssertEqual(try fixture.arguments(), ["pr", "merge", "123", "--squash", "--auto", "--delete-branch"])
    }
}

private extension GitHubPullRequestToolExecutorTests {
    struct GitHubCLIFixture {
        var root: URL
        var argumentsFile: URL
        var git: GitToolExecutor

        func arguments() throws -> [String] {
            try String(contentsOf: argumentsFile, encoding: .utf8)
                .split(separator: "\n")
                .map(String.init)
        }

        func router() -> ToolRouter {
            ToolRouter(workspaceRoot: root, git: git)
        }
    }

    func makeFixture() throws -> GitHubCLIFixture {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeGitHubCLI = try makeFakeGitHubCLI(in: root, argumentsFile: argumentsFile)
        return GitHubCLIFixture(
            root: root,
            argumentsFile: argumentsFile,
            git: GitToolExecutor(githubCLIExecutable: fakeGitHubCLI)
        )
    }

    func makeReviewCommentFixture() throws -> GitHubCLIFixture {
        let root = try makeTempDirectory()
        let argumentsFile = root.appendingPathComponent("gh-args.txt")
        let fakeGitHubCLI = try makeReviewCommentFakeGitHubCLI(in: root, argumentsFile: argumentsFile)
        return GitHubCLIFixture(
            root: root,
            argumentsFile: argumentsFile,
            git: GitToolExecutor(githubCLIExecutable: fakeGitHubCLI)
        )
    }

    func makeReviewCommentFakeGitHubCLI(in root: URL, argumentsFile: URL) throws -> URL {
        let script = root.appendingPathComponent("fake-gh-review-comment")
        let argumentsPath = argumentsFile.path.replacingOccurrences(of: "'", with: "'\\''")
        try """
        #!/bin/sh
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
          echo '{"number":123,"headRefOid":"abc123"}'
        elif [ "$1" = "repo" ] && [ "$2" = "view" ]; then
          echo '{"nameWithOwner":"example/repo"}'
        elif [ "$1" = "api" ]; then
          printf '%s\\n' "$@" > '\(argumentsPath)'
          echo '{"html_url":"https://github.com/example/repo/pull/123#discussion_r99"}'
        else
          printf '%s\\n' "$@" > '\(argumentsPath)'
          echo 'unexpected fake gh invocation' >&2
          exit 1
        fi
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
