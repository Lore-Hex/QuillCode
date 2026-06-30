import XCTest
@testable import QuillCodeTools

final class GitWorktreeToolExecutorTests: XCTestCase {
    func testCreateListOpenAndRemoveSibling() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let worktreeName = "quillcode-worktree-\(UUID().uuidString)"
        let worktree = parent.appendingPathComponent(worktreeName).standardizedFileURL
        let branch = "quillcode-\(UUID().uuidString.prefix(8))"
        let git = GitToolExecutor()

        let create = git.createWorktree(cwd: root, path: worktreeName, branch: String(branch))

        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        XCTAssertEqual(create.artifacts, [worktree.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.appendingPathComponent(".git").path))

        let list = git.listWorktrees(cwd: root)
        XCTAssertTrue(list.ok, "\(list.error ?? "") \(list.stderr)")
        XCTAssertTrue(list.stdout.contains(worktree.path), list.stdout)
        XCTAssertTrue(list.stdout.contains(String(branch)), list.stdout)

        let open = git.openWorktree(cwd: root, path: worktreeName)

        XCTAssertTrue(open.ok, "\(open.error ?? "") \(open.stderr)")
        XCTAssertEqual(open.artifacts, [worktree.path])
        XCTAssertTrue(open.stdout.contains(worktree.path), open.stdout)

        let remove = git.removeWorktree(cwd: root, path: worktreeName)

        XCTAssertTrue(remove.ok, "\(remove.error ?? "") \(remove.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))

        let prune = git.pruneWorktrees(cwd: root, dryRun: true, verbose: true)
        XCTAssertTrue(prune.ok, "\(prune.error ?? "") \(prune.stderr)")
    }

    func testCreateRejectsUnsafePath() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        let result = GitToolExecutor().createWorktree(cwd: root, path: "../outside")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("outside the workspace") == true, result.error ?? "")
    }

    func testCreateRejectsWorktreeThroughParentSymlinkEscape() throws {
        let parent = try makeTempDirectory()
        let workspace = parent.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let outside = try makeTempDirectory()
        // A symlink in the workspace's PARENT that points outside it. `escape/wt` is lexically under the
        // parent but resolves into `outside` — the lexical-only check would miss it; the shared
        // WorkspaceBoundary symlink-resolved check must reject it.
        try FileManager.default.createSymbolicLink(
            at: parent.appendingPathComponent("escape"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try GitWorktreeToolExecutor.safePath("escape/wt", cwd: workspace)) { error in
            XCTAssertTrue("\(error)".contains("outside the workspace"), "\(error)")
        }
        // A legitimate sibling worktree (no symlink) is still allowed.
        XCTAssertNoThrow(try GitWorktreeToolExecutor.safePath("project-wt", cwd: workspace))
    }

    func testCreateRejectsUnsafeBranchAndBaseNames() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let git = GitToolExecutor()

        let unsafeBranch = git.createWorktree(cwd: root, path: "safe-worktree", branch: "--bad")
        let unsafeBase = git.createWorktree(cwd: root, path: "safe-worktree", base: "../main")

        XCTAssertFalse(unsafeBranch.ok)
        XCTAssertTrue(unsafeBranch.error?.contains("unsupported characters") == true, unsafeBranch.error ?? "")
        XCTAssertFalse(unsafeBase.ok)
        XCTAssertTrue(unsafeBase.error?.contains("unsupported characters") == true, unsafeBase.error ?? "")
    }

    func testOpenAndRemoveRejectUnregisteredPath() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let parent = root.deletingLastPathComponent()
        let unrelatedName = "not-a-worktree-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent(unrelatedName),
            withIntermediateDirectories: true
        )

        let git = GitToolExecutor()
        let open = git.openWorktree(cwd: root, path: unrelatedName)
        let remove = git.removeWorktree(cwd: root, path: unrelatedName, force: true)

        XCTAssertFalse(open.ok)
        XCTAssertTrue(open.error?.contains("not registered") == true, open.error ?? "")
        XCTAssertFalse(remove.ok)
        XCTAssertTrue(remove.error?.contains("not registered") == true, remove.error ?? "")
    }
}
