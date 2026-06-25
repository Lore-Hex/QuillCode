import XCTest
@testable import QuillCodeApp

final class WorkspaceWorktreeListSurfaceBuilderTests: XCTestCase {
    func testChoicesParsePorcelainBranchesAndSkipCurrentProject() {
        let stdout = """
        worktree /repo/quill
        HEAD aaaaaaa
        branch refs/heads/main

        worktree /repo/quill-feature
        HEAD bbbbbbb
        branch refs/heads/feature/picker

        worktree /repo/quill-detached
        HEAD ccccccc
        detached

        """

        let choices = WorkspaceWorktreeListSurfaceBuilder.choices(
            fromPorcelain: stdout,
            selectedProjectPath: "/repo/quill"
        )

        XCTAssertEqual(choices.map(\.path), ["/repo/quill-feature", "/repo/quill-detached"])
        XCTAssertEqual(choices.map(\.title), ["quill-feature", "quill-detached"])
        XCTAssertEqual(choices.map(\.detail), ["feature/picker", "Detached HEAD"])
    }

    func testChoicesHandlesBareAndTrailingEntryWithoutBlankLine() {
        let choices = WorkspaceWorktreeListSurfaceBuilder.choices(
            fromPorcelain: """
            worktree /repo/main
            HEAD aaaaaaa
            bare
            worktree /repo/other
            HEAD bbbbbbb
            """,
            selectedProjectPath: nil
        )

        XCTAssertEqual(choices.map(\.path), ["/repo/main", "/repo/other"])
        XCTAssertEqual(choices.map(\.detail), ["Bare worktree", "Registered worktree"])
    }
}
