import XCTest
import QuillCodeCore

final class GitHubPullRequestToolRouterTests: XCTestCase {
    func testToolRouterRoutesPullRequestCreate() throws {
        let fixture = try makeGitHubPullRequestFixture()
        let router = fixture.router()

        let result = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestCreate.name,
            argumentsJSON: #"{"title":"Add PR route","base":"main","draft":true}"#
        ))

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(fixture, ["pr", "create", "--title", "Add PR route", "--base", "main", "--draft"])
    }

    func testToolRouterRoutesPullRequestReadTools() throws {
        let fixture = try makeGitHubPullRequestFixture()
        let router = fixture.router()

        let view = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestView.name,
            argumentsJSON: #"{"selector":"123"}"#
        ))
        assertGitHubToolResultOK(view)
        try assertGitHubArguments(fixture, ["pr", "view", "123", "--comments"])

        let checks = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestChecks.name,
            argumentsJSON: #"{"selector":"123"}"#
        ))
        assertGitHubToolResultOK(checks)
        try assertGitHubArguments(fixture, ["pr", "checks", "123"])

        let diff = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestDiff.name,
            argumentsJSON: #"{"selector":"123"}"#
        ))
        assertGitHubToolResultOK(diff)
        try assertGitHubArguments(fixture, ["pr", "diff", "123"])

        let checkout = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestCheckout.name,
            argumentsJSON: #"{"selector":"123","branch":"review/pr-123"}"#
        ))
        assertGitHubToolResultOK(checkout)
        try assertGitHubArguments(fixture, ["pr", "checkout", "123", "--branch", "review/pr-123"])
    }

    func testToolRouterRoutesPullRequestEditTools() throws {
        let fixture = try makeGitHubPullRequestFixture()
        let router = fixture.router()

        let reviewers = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestReviewers.name,
            argumentsJSON: #"{"selector":"123","add":["alice","myorg/team-name"],"remove":"bob"}"#
        ))
        assertGitHubToolResultOK(reviewers)
        try assertGitHubArguments(fixture, [
            "pr", "edit", "123",
            "--add-reviewer", "alice,myorg/team-name",
            "--remove-reviewer", "bob"
        ])

        let labels = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestLabels.name,
            argumentsJSON: #"{"selector":"123","add":["merge-train","needs review"],"remove":"blocked"}"#
        ))
        assertGitHubToolResultOK(labels)
        try assertGitHubArguments(fixture, [
            "pr", "edit", "123",
            "--add-label", "merge-train,needs review",
            "--remove-label", "blocked"
        ])

        let comment = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestComment.name,
            argumentsJSON: #"{"selector":"123","body":"Ready for review."}"#
        ))
        assertGitHubToolResultOK(comment)
        try assertGitHubArguments(fixture, ["pr", "comment", "123", "--body", "Ready for review."])

        let lifecycle = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestLifecycle.name,
            argumentsJSON: #"{"selector":"123","action":"reopen"}"#
        ))
        assertGitHubToolResultOK(lifecycle)
        try assertGitHubArguments(fixture, ["pr", "reopen", "123"])
    }

    func testToolRouterRoutesPullRequestReviewTools() throws {
        let fixture = try makeGitHubPullRequestFixture()
        let router = fixture.router()

        let review = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestReview.name,
            argumentsJSON: #"{"selector":"123","action":"approve"}"#
        ))
        assertGitHubToolResultOK(review)
        try assertGitHubArguments(fixture, ["pr", "review", "123", "--approve"])

        let reviewCommentFixture = try makeGitHubPullRequestReviewCommentFixture()
        let reviewComment = reviewCommentFixture.router().execute(ToolCall(
            name: ToolDefinition.gitPullRequestReviewComment.name,
            argumentsJSON: #"{"selector":"123","path":"Sources/App.swift","line":42,"body":"Looks good."}"#
        ))
        assertGitHubToolResultOK(reviewComment)
        try assertGitHubArguments(reviewCommentFixture, [
            "api", "repos/example/repo/pulls/123/comments",
            "--raw-field", "body=Looks good.",
            "--raw-field", "commit_id=abc123",
            "--raw-field", "path=Sources/App.swift",
            "--field", "line=42",
            "--raw-field", "side=RIGHT"
        ])

        let reviewReplyFixture = try makeGitHubPullRequestReviewCommentFixture()
        let reviewReply = reviewReplyFixture.router().execute(ToolCall(
            name: ToolDefinition.gitPullRequestReviewReply.name,
            argumentsJSON: #"{"selector":"123","commentId":99,"body":"Updated this."}"#
        ))
        assertGitHubToolResultOK(reviewReply)
        try assertGitHubArguments(reviewReplyFixture, [
            "api",
            "repos/example/repo/pulls/123/comments/99/replies",
            "--raw-field",
            "body=Updated this."
        ])

        let reviewThreadsFixture = try makeGitHubPullRequestReviewCommentFixture()
        let reviewThreads = reviewThreadsFixture.router().execute(ToolCall(
            name: ToolDefinition.gitPullRequestReviewThreads.name,
            argumentsJSON: #"{"selector":"123"}"#
        ))
        assertGitHubToolResultOK(reviewThreads)
        let reviewThreadsArguments = try reviewThreadsFixture.arguments()
        XCTAssertEqual(Array(reviewThreadsArguments.prefix(4)), ["api", "graphql", "--raw-field", "owner=example"])
        XCTAssertTrue(reviewThreadsArguments.joined(separator: "\n").contains("reviewThreads(first: 50)"))

        let reviewThreadFixture = try makeGitHubPullRequestReviewCommentFixture()
        let reviewThread = reviewThreadFixture.router().execute(ToolCall(
            name: ToolDefinition.gitPullRequestReviewThread.name,
            argumentsJSON: #"{"threadId":"PRRT_kwDOExample","action":"unresolve"}"#
        ))
        assertGitHubToolResultOK(reviewThread)
        try assertGitHubArguments(reviewThreadFixture, [
            "api",
            "graphql",
            "--raw-field",
            "threadId=PRRT_kwDOExample",
            "--raw-field",
            "query=mutation($threadId: ID!) { unresolveReviewThread(input: {threadId: $threadId}) { thread { id isResolved } } }"
        ])
    }

    func testToolRouterRoutesPullRequestMergeTool() throws {
        let fixture = try makeGitHubPullRequestFixture()
        let router = fixture.router()

        let merge = router.execute(ToolCall(
            name: ToolDefinition.gitPullRequestMerge.name,
            argumentsJSON: #"{"selector":"123","method":"squash","auto":"true","deleteBranch":true}"#
        ))

        assertGitHubToolResultOK(merge)
        try assertGitHubArguments(fixture, ["pr", "merge", "123", "--squash", "--auto", "--delete-branch"])
    }
}
