import XCTest
@testable import QuillCodeTools

final class GitBranchStatusTests: XCTestCase {
    func testPlainBranchWithoutUpstream() {
        let status = GitBranchStatus.parse(statusShortBranchOutput: "## main\n")
        XCTAssertEqual(status?.branch, "main")
        XCTAssertNil(status?.upstream)
        XCTAssertEqual(status?.ahead, 0)
        XCTAssertEqual(status?.behind, 0)
        XCTAssertFalse(status?.isDetached ?? true)
        XCTAssertEqual(status?.compactLabel, "main")
    }

    func testTrackingBranchWithAheadAndBehind() {
        let status = GitBranchStatus.parse(
            statusShortBranchOutput: "## feature/x...origin/feature/x [ahead 2, behind 1]\n M Sources/App.swift\n"
        )
        XCTAssertEqual(status?.branch, "feature/x")
        XCTAssertEqual(status?.upstream, "origin/feature/x")
        XCTAssertEqual(status?.ahead, 2)
        XCTAssertEqual(status?.behind, 1)
        XCTAssertEqual(status?.compactLabel, "feature/x ↑2 ↓1")
    }

    func testAheadOnlyAndBehindOnly() {
        let ahead = GitBranchStatus.parse(statusShortBranchOutput: "## work...origin/work [ahead 5]")
        XCTAssertEqual(ahead?.ahead, 5)
        XCTAssertEqual(ahead?.behind, 0)
        XCTAssertEqual(ahead?.compactLabel, "work ↑5")

        let behind = GitBranchStatus.parse(statusShortBranchOutput: "## work...origin/work [behind 3]")
        XCTAssertEqual(behind?.ahead, 0)
        XCTAssertEqual(behind?.behind, 3)
        XCTAssertEqual(behind?.compactLabel, "work ↓3")
    }

    func testUpstreamGoneKeepsUpstreamWithoutCounts() {
        let status = GitBranchStatus.parse(statusShortBranchOutput: "## feature/x...origin/feature/x [gone]")
        XCTAssertEqual(status?.branch, "feature/x")
        XCTAssertEqual(status?.upstream, "origin/feature/x")
        XCTAssertEqual(status?.ahead, 0)
        XCTAssertEqual(status?.behind, 0)
    }

    func testTrackingBranchUpToDate() {
        let status = GitBranchStatus.parse(statusShortBranchOutput: "## feature/x...origin/feature/x")
        XCTAssertEqual(status?.branch, "feature/x")
        XCTAssertEqual(status?.upstream, "origin/feature/x")
        XCTAssertEqual(status?.compactLabel, "feature/x")
    }

    func testDetachedHead() {
        let status = GitBranchStatus.parse(statusShortBranchOutput: "## HEAD (no branch)\n M file.txt")
        XCTAssertTrue(status?.isDetached ?? false)
        XCTAssertEqual(status?.compactLabel, "(detached)")
    }

    func testEmptyOrUnparseableReturnsNil() {
        XCTAssertNil(GitBranchStatus.parse(statusShortBranchOutput: ""))
        XCTAssertNil(GitBranchStatus.parse(statusShortBranchOutput: " M only-changes.txt\n"))
        XCTAssertNil(GitBranchStatus.parse(statusShortBranchOutput: "not a header"))
    }
}
