import XCTest
@testable import QuillCodeTools

final class GitHubPullRequestMergeToolExecutorTests: XCTestCase {
    func testPullRequestMergeUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.mergePullRequest(
            cwd: fixture.root,
            selector: "123",
            method: "rebase",
            auto: true,
            deleteBranch: true
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(fixture, ["pr", "merge", "123", "--rebase", "--auto", "--delete-branch"])
    }

    func testPullRequestMergeDefaultsToSquashAndRejectsInvalidMethod() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.mergePullRequest(cwd: fixture.root, selector: "123")

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(fixture, ["pr", "merge", "123", "--squash"])

        XCTAssertFalse(fixture.git.mergePullRequest(cwd: fixture.root, selector: "123", method: "octopus").ok)
        try assertGitHubArguments(fixture, ["pr", "merge", "123", "--squash"])
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
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeReviewCommentID(99), 99)
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeReviewThreadID("PRRT_kwDOExample"), "PRRT_kwDOExample")
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeReviewThreadAction("reopen"), "unresolve")
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeMergeFlag(nil), "--squash")
        XCTAssertEqual(try GitHubPullRequestInputValidator.safeMergeFlag("merge-commit"), "--merge")
        XCTAssertEqual(
            GitHubPullRequestOutputParser.extractURLs(from: """
            created https://github.com/example/repo/pull/12 ok {"html_url":"https://github.com/example/repo/pull/12#discussion_r1"}
            """),
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
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeReviewCommentID(0))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeReviewThreadID("bad id"))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeReviewThreadAction("delete"))
        XCTAssertThrowsError(try GitHubPullRequestInputValidator.safeMergeFlag("octopus"))
    }
}
