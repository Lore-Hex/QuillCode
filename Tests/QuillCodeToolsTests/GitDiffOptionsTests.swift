import XCTest
@testable import QuillCodeTools

final class GitDiffOptionsTests: XCTestCase {
    func testBuildsArgumentsForEveryComparison() throws {
        XCTAssertEqual(try GitDiffOptions().gitArguments, ["diff"])
        XCTAssertEqual(try GitDiffOptions(staged: true).gitArguments, ["diff", "--staged"])
        XCTAssertEqual(
            try GitDiffOptions(commit: " HEAD ").gitArguments,
            ["show", "--format=", "--no-ext-diff", "--find-renames", "--find-copies", "HEAD", "--"]
        )
        XCTAssertEqual(
            try GitDiffOptions(baseBranch: " origin/main ").gitArguments,
            ["diff", "--no-ext-diff", "--find-renames", "--find-copies", "origin/main...HEAD", "--"]
        )
    }

    func testRejectsAmbiguousOrUnsafeComparisons() {
        XCTAssertThrowsError(try GitDiffOptions(staged: true, commit: "HEAD")) { error in
            XCTAssertEqual(String(describing: error), "Git diff accepts only one of staged, commit, or baseBranch.")
        }
        XCTAssertThrowsError(try GitDiffOptions(commit: " ")) { error in
            XCTAssertEqual(String(describing: error), "Git diff commit or base branch is required.")
        }
        XCTAssertThrowsError(try GitDiffOptions(baseBranch: "main; touch /tmp/escape"))
        XCTAssertThrowsError(try GitDiffOptions(commit: "--output=/tmp/escape"))
    }
}
