import XCTest

final class GitHubPullRequestEditToolExecutorTests: XCTestCase {
    func testPullRequestReviewersUseGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.updatePullRequestReviewers(
            cwd: fixture.root,
            selector: "123",
            add: ["alice", "myorg/platform-team", "alice"],
            remove: ["bob"]
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(fixture, [
            "pr", "edit", "123",
            "--add-reviewer", "alice,myorg/platform-team",
            "--remove-reviewer", "bob"
        ])
    }

    func testPullRequestReviewersRequireReviewerAndValidateNames() throws {
        let fixture = try makeGitHubPullRequestFixture()

        XCTAssertFalse(fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123").ok)
        XCTAssertFalse(
            fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123", add: ["bad reviewer"]).ok
        )
        XCTAssertFalse(fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123", add: ["-bad"]).ok)
        XCTAssertFalse(
            fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123", add: ["org/team/extra"]).ok
        )
        assertNoGitHubInvocation(fixture)
    }

    func testPullRequestLabelsUseGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.updatePullRequestLabels(
            cwd: fixture.root,
            selector: "123",
            add: ["merge-train", "needs review", "merge-train"],
            remove: ["blocked"]
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(fixture, [
            "pr", "edit", "123",
            "--add-label", "merge-train,needs review",
            "--remove-label", "blocked"
        ])
    }

    func testPullRequestLabelsRequireLabelAndValidateNames() throws {
        let fixture = try makeGitHubPullRequestFixture()

        XCTAssertFalse(fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123").ok)
        XCTAssertFalse(fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123", add: ["-bad"]).ok)
        XCTAssertFalse(
            fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123", add: ["bad,label"]).ok
        )
        XCTAssertFalse(
            fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123", add: ["bad\nlabel"]).ok
        )
        assertNoGitHubInvocation(fixture)
    }

    func testPullRequestCommentUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.commentOnPullRequest(
            cwd: fixture.root,
            selector: "123",
            body: "Ready for review."
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(fixture, ["pr", "comment", "123", "--body", "Ready for review."])
    }

    func testPullRequestCommentRequiresBody() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.commentOnPullRequest(cwd: fixture.root, selector: "123", body: " ")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("comment body is required") == true, result.error ?? "")
        assertNoGitHubInvocation(fixture)
    }
}
