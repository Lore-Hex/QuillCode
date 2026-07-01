import XCTest

final class GitHubPullRequestReviewToolExecutorTests: XCTestCase {
    func testPullRequestReviewUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.reviewPullRequest(
            cwd: fixture.root,
            selector: "123",
            action: "request_changes",
            body: "Please add tests."
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(
            fixture,
            ["pr", "review", "123", "--request-changes", "--body", "Please add tests."]
        )
    }

    func testPullRequestReviewAllowsApprovalWithoutBody() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123", action: "approve")

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(fixture, ["pr", "review", "123", "--approve"])
    }

    func testPullRequestReviewRequiresValidActionAndBodyWhenNeeded() throws {
        let fixture = try makeGitHubPullRequestFixture()

        XCTAssertFalse(
            fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123", action: "merge", body: "ok").ok
        )
        XCTAssertFalse(
            fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123", action: "comment", body: " ").ok
        )
        assertNoGitHubInvocation(fixture)
    }

    func testPullRequestReviewCommentUsesGitHubAPIArguments() throws {
        let fixture = try makeGitHubPullRequestReviewCommentFixture()

        let result = fixture.git.commentOnPullRequestLine(
            cwd: fixture.root,
            selector: "123",
            path: "Sources/App.swift",
            line: 42,
            side: "right",
            body: "Check this edge case.",
            startLine: 40
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123#discussion_r99"])
        try assertGitHubArguments(fixture, [
            "api", "repos/example/repo/pulls/123/comments",
            "--raw-field", "body=Check this edge case.",
            "--raw-field", "commit_id=abc123",
            "--raw-field", "path=Sources/App.swift",
            "--field", "line=42",
            "--raw-field", "side=RIGHT",
            "--field", "start_line=40",
            "--raw-field", "start_side=RIGHT"
        ])
    }

    func testPullRequestReviewCommentValidatesInputsBeforeGitHubCalls() throws {
        let fixture = try makeGitHubPullRequestReviewCommentFixture()

        XCTAssertFalse(
            fixture.git.commentOnPullRequestLine(cwd: fixture.root, path: "../App.swift", line: 42, body: "Comment").ok
        )
        XCTAssertFalse(
            fixture.git.commentOnPullRequestLine(cwd: fixture.root, path: "App.swift", line: 0, body: "Comment").ok
        )
        XCTAssertFalse(
            fixture.git.commentOnPullRequestLine(
                cwd: fixture.root,
                path: "App.swift",
                line: 42,
                side: "BOTH",
                body: "Comment"
            ).ok
        )
        XCTAssertFalse(
            fixture.git.commentOnPullRequestLine(
                cwd: fixture.root,
                path: "App.swift",
                line: 42,
                body: " ",
                startLine: 40
            ).ok
        )
        XCTAssertFalse(
            fixture.git.commentOnPullRequestLine(
                cwd: fixture.root,
                path: "App.swift",
                line: 42,
                body: "Comment",
                startLine: 50
            ).ok
        )
        assertNoGitHubInvocation(fixture)
    }

    func testPullRequestReviewReplyUsesGitHubAPIArguments() throws {
        let fixture = try makeGitHubPullRequestReviewCommentFixture()

        let result = fixture.git.replyToPullRequestReviewComment(
            cwd: fixture.root,
            selector: "123",
            commentID: 99,
            body: "Thanks, updated this."
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123#discussion_r99"])
        try assertGitHubArguments(fixture, [
            "api",
            "repos/example/repo/pulls/123/comments/99/replies",
            "--raw-field",
            "body=Thanks, updated this."
        ])
    }

    func testPullRequestReviewThreadsUsesGitHubGraphQLQuery() throws {
        let fixture = try makeGitHubPullRequestReviewCommentFixture()

        let result = fixture.git.listPullRequestReviewThreads(cwd: fixture.root, selector: "123")

        assertGitHubToolResultOK(result)
        let arguments = try fixture.arguments()
        XCTAssertEqual(Array(arguments.prefix(7)), [
            "api",
            "graphql",
            "--raw-field",
            "owner=example",
            "--raw-field",
            "name=repo",
            "--field"
        ])
        XCTAssertEqual(arguments[7], "number=123")
        XCTAssertEqual(arguments[8], "--raw-field")
        XCTAssertTrue(arguments[9].contains("query=query($owner: String!"), arguments[9])
        XCTAssertTrue(arguments[9].contains("reviewThreads(first: 50)"), arguments[9])
        XCTAssertTrue(arguments[9].contains("databaseId"), arguments[9])
        XCTAssertTrue(arguments[9].contains("isResolved"), arguments[9])
    }

    func testPullRequestReviewThreadUsesGitHubGraphQLMutation() throws {
        let fixture = try makeGitHubPullRequestReviewCommentFixture()

        let result = fixture.git.updatePullRequestReviewThread(
            cwd: fixture.root,
            threadID: "PRRT_kwDOExample",
            action: "resolve"
        )

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(fixture, [
            "api",
            "graphql",
            "--raw-field",
            "threadId=PRRT_kwDOExample",
            "--raw-field",
            "query=mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { id isResolved } } }"
        ])
    }

    func testPullRequestReviewReplyAndThreadValidateInputsBeforeGitHubCalls() throws {
        let fixture = try makeGitHubPullRequestReviewCommentFixture()

        XCTAssertFalse(fixture.git.replyToPullRequestReviewComment(cwd: fixture.root, commentID: 0, body: "Reply").ok)
        XCTAssertFalse(fixture.git.replyToPullRequestReviewComment(cwd: fixture.root, commentID: 1, body: " ").ok)
        XCTAssertFalse(
            fixture.git.updatePullRequestReviewThread(cwd: fixture.root, threadID: "bad id", action: "resolve").ok
        )
        XCTAssertFalse(
            fixture.git.updatePullRequestReviewThread(
                cwd: fixture.root,
                threadID: "PRRT_kwDOExample",
                action: "delete"
            ).ok
        )
        assertNoGitHubInvocation(fixture)
    }
}
