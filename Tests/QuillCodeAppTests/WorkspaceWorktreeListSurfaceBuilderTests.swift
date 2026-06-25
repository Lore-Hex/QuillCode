import XCTest
@testable import QuillCodeApp

final class WorkspaceWorktreeListSurfaceBuilderTests: XCTestCase {
    func testChoiceLoadStateTracksLoadingSuccessEmptyAndFailure() {
        let choice = WorkspaceWorktreeChoice(
            path: "/repo/quill-feature",
            title: "quill-feature",
            detail: "feature/picker"
        )

        XCTAssertTrue(QuillCodeWorktreeChoiceLoadState.loading.isLoading)

        let loaded = QuillCodeWorktreeChoiceLoadState.loaded(.init(choices: [choice]))
        XCTAssertFalse(loaded.isLoading)
        XCTAssertTrue(loaded.hasLoaded)
        XCTAssertEqual(loaded.choices, [choice])
        XCTAssertNil(loaded.errorMessage)

        let empty = QuillCodeWorktreeChoiceLoadState.loaded(.init())
        XCTAssertFalse(empty.isLoading)
        XCTAssertTrue(empty.hasLoaded)
        XCTAssertEqual(empty.choices, [])
        XCTAssertNil(empty.errorMessage)

        let failed = QuillCodeWorktreeChoiceLoadState.loaded(.init(errorMessage: "not a git repo"))
        XCTAssertFalse(failed.isLoading)
        XCTAssertTrue(failed.hasLoaded)
        XCTAssertEqual(failed.choices, [])
        XCTAssertEqual(failed.errorMessage, "not a git repo")
    }

    func testChoiceLoadRequestReturnsVisibleErrorForNonGitDirectory() throws {
        let directory = try makeQuillCodeTestDirectory()

        let load = WorkspaceWorktreeChoiceLoadRequest(
            workspaceRoot: directory,
            selectedProject: nil
        ).load()

        XCTAssertEqual(load.choices, [])
        XCTAssertTrue(load.errorMessage?.isEmpty == false)
    }

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
