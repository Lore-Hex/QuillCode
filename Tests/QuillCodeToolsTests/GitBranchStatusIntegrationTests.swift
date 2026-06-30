import XCTest
@testable import QuillCodeTools

final class GitBranchStatusIntegrationTests: XCTestCase {
    func testRealRepoStatusParsesCurrentBranch() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let result = GitLocalToolExecutor().status(cwd: root)
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")

        let status = try XCTUnwrap(GitBranchStatus.parse(statusShortBranchOutput: result.stdout))
        // A fresh repo has no upstream, so ahead/behind are zero and the branch is
        // whatever git initialized (main or master).
        XCTAssertFalse(status.branch.isEmpty)
        XCTAssertNil(status.upstream)
        XCTAssertEqual(status.ahead, 0)
        XCTAssertEqual(status.behind, 0)
        XCTAssertFalse(status.isDetached)
        XCTAssertEqual(status.compactLabel, status.branch)
    }

    func testRealRepoAheadOfUpstream() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let shell = ShellToolExecutor()
        // Create a bare upstream, push, then commit locally to go ahead by one.
        let remote = root.deletingLastPathComponent().appendingPathComponent("upstream.git")
        XCTAssertTrue(shell.run(.init(command: "git init --bare '\(remote.path)'", cwd: root)).ok)
        XCTAssertTrue(shell.run(.init(command: "git remote add origin '\(remote.path)' && git push -u origin HEAD", cwd: root)).ok)
        try "ahead\n".write(to: root.appendingPathComponent("ahead.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(shell.run(.init(command: "git add ahead.txt && git commit -m ahead", cwd: root)).ok)

        let result = GitLocalToolExecutor().status(cwd: root)
        let status = try XCTUnwrap(GitBranchStatus.parse(statusShortBranchOutput: result.stdout))
        XCTAssertEqual(status.ahead, 1)
        XCTAssertEqual(status.behind, 0)
        XCTAssertNotNil(status.upstream)
        XCTAssertTrue(status.compactLabel.contains("↑1"))
    }
}
