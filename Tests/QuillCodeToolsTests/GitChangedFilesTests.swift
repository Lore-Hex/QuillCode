import XCTest
@testable import QuillCodeTools

final class GitChangedFilesTests: XCTestCase {
    func testParsesModifiedUntrackedAndStagedPaths() {
        let paths = GitChangedFiles.parse(statusShortBranchOutput: """
        ## main...origin/main [ahead 1]
         M Sources/App.swift
        ?? Sources/New.swift
        MM Sources/Both.swift
        A  Sources/Added.swift
         D Sources/Gone.swift
        """)
        XCTAssertEqual(paths, [
            "Sources/App.swift",
            "Sources/New.swift",
            "Sources/Both.swift",
            "Sources/Added.swift",
            "Sources/Gone.swift"
        ])
    }

    func testKeepsPostArrowPathForRenames() {
        let paths = GitChangedFiles.parse(statusShortBranchOutput: """
        ## main
        R  Sources/Old.swift -> Sources/Renamed.swift
        """)
        XCTAssertEqual(paths, ["Sources/Renamed.swift"])
        XCTAssertFalse(paths.contains("Sources/Old.swift"))
    }

    func testDoesNotSplitNonRenameLinesContainingArrowText() {
        // An untracked file whose name literally contains " -> " must be kept whole.
        let paths = GitChangedFiles.parse(statusShortBranchOutput: """
        ## main
        ?? "Sources/a -> b.txt"
        """)
        XCTAssertEqual(paths, ["Sources/a -> b.txt"])
    }

    func testUnquotesPathsWithSpecialCharacters() {
        let paths = GitChangedFiles.parse(statusShortBranchOutput: """
        ## main
         M "Sources/Has Space.swift"
        """)
        XCTAssertEqual(paths, ["Sources/Has Space.swift"])
    }

    func testSkipsBranchHeaderAndEmptyOutput() {
        XCTAssertTrue(GitChangedFiles.parse(statusShortBranchOutput: "## main...origin/main\n").isEmpty)
        XCTAssertTrue(GitChangedFiles.parse(statusShortBranchOutput: "").isEmpty)
        // The `## ` header is never emitted as a changed path.
        let paths = GitChangedFiles.parse(statusShortBranchOutput: "## feature/x [ahead 3]\n M a.txt\n")
        XCTAssertEqual(paths, ["a.txt"])
        XCTAssertFalse(paths.contains(where: { $0.contains("feature/x") }))
    }
}
