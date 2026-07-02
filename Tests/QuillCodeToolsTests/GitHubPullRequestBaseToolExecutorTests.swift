import XCTest
@testable import QuillCodeTools

final class GitHubPullRequestBaseToolExecutorTests: XCTestCase {
    func testListPullRequestsUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.listPullRequests(cwd: fixture.root, state: "merged", limit: 25)

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(fixture, ["pr", "list", "--state", "merged", "--limit", "25"])
    }

    func testCreatePullRequestUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.createPullRequest(
            cwd: fixture.root,
            title: "Add PR tool",
            body: "Adds structured pull request creation.",
            base: "main",
            head: "feature/pr-tool",
            draft: true
        )

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(fixture, [
            "pr", "create",
            "--title", "Add PR tool",
            "--body", "Adds structured pull request creation.",
            "--base", "main",
            "--head", "feature/pr-tool",
            "--draft"
        ])
    }

    func testCreatePullRequestRequiresTitleUnlessFillIsEnabled() throws {
        let fixture = try makeGitHubPullRequestFixture()

        XCTAssertFalse(fixture.git.createPullRequest(cwd: fixture.root, title: " ").ok)

        let result = fixture.git.createPullRequest(cwd: fixture.root, fill: true)

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(fixture, ["pr", "create", "--fill"])
    }

    func testViewPullRequestUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.viewPullRequest(cwd: fixture.root, selector: "123")

        assertGitHubToolResultOK(result)
        XCTAssertEqual(result.artifacts, ["https://github.com/example/repo/pull/123"])
        try assertGitHubArguments(fixture, ["pr", "view", "123", "--comments"])
    }

    func testPullRequestChecksUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.pullRequestChecks(
            cwd: fixture.root,
            selector: "https://github.com/example/repo/pull/123"
        )

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(
            fixture,
            ["pr", "checks", "https://github.com/example/repo/pull/123"]
        )
    }

    func testPullRequestDiffUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.diffPullRequest(cwd: fixture.root, selector: "123")

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(fixture, ["pr", "diff", "123"])
    }

    func testPullRequestCheckoutUsesGitHubCLIArguments() throws {
        let fixture = try makeGitHubPullRequestFixture()

        let result = fixture.git.checkoutPullRequest(
            cwd: fixture.root,
            selector: "123",
            branch: "review/pr-123"
        )

        assertGitHubToolResultOK(result)
        try assertGitHubArguments(fixture, ["pr", "checkout", "123", "--branch", "review/pr-123"])
    }

    func testPullRequestToolsRejectUnsafeSelector() throws {
        let fixture = try makeGitHubPullRequestFixture()

        XCTAssertFalse(fixture.git.listPullRequests(cwd: fixture.root, state: "draft").ok)
        XCTAssertFalse(fixture.git.listPullRequests(cwd: fixture.root, limit: 101).ok)
        XCTAssertFalse(fixture.git.viewPullRequest(cwd: fixture.root, selector: "--json").ok)
        XCTAssertFalse(fixture.git.pullRequestChecks(cwd: fixture.root, selector: "feature branch").ok)
        XCTAssertFalse(fixture.git.diffPullRequest(cwd: fixture.root, selector: "--patch").ok)
        XCTAssertFalse(fixture.git.checkoutPullRequest(cwd: fixture.root, selector: "123 --web").ok)
        XCTAssertFalse(fixture.git.checkoutPullRequest(cwd: fixture.root, selector: "123", branch: "--bad").ok)
        XCTAssertFalse(
            fixture.git.updatePullRequestReviewers(cwd: fixture.root, selector: "123 --web", add: ["alice"]).ok
        )
        XCTAssertFalse(
            fixture.git.updatePullRequestLabels(cwd: fixture.root, selector: "123 --web", add: ["merge-train"]).ok
        )
        XCTAssertFalse(
            fixture.git.commentOnPullRequest(cwd: fixture.root, selector: "123 --web", body: "Comment").ok
        )
        XCTAssertFalse(
            fixture.git.reviewPullRequest(cwd: fixture.root, selector: "123 --web", action: "approve").ok
        )
        XCTAssertFalse(fixture.git.mergePullRequest(cwd: fixture.root, selector: "123 --web").ok)
        XCTAssertThrowsError(try GitToolExecutor.safePullRequestSelector("--web"))
    }
}
