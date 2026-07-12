import XCTest
@testable import QuillCodeTools

final class GitWorktreeToolExecutorTests: XCTestCase {
    func testManagedSnapshotFreezesValidatedLocalFileContent() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let source = root.appendingPathComponent("notes.txt")
        let snapshotRoot = try makeTempDirectory()
        try "captured\n".write(to: source, atomically: true, encoding: .utf8)

        let snapshot = try ManagedWorktreeTransferSnapshot.capture(
            sourceRoot: root,
            temporaryDirectory: snapshotRoot,
            runner: GitProcessRunner()
        )
        try "changed later\n".write(to: source, atomically: true, encoding: .utf8)

        let frozen = try XCTUnwrap(snapshot.files.first { $0.relativePath == "notes.txt" })
        XCTAssertEqual(try String(contentsOf: frozen.snapshotURL), "captured\n")
    }

    func testManagedCreateStartsDetachedAndPreservesLocalChangeState() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let staged = root.appendingPathComponent("staged.txt")
        let unstaged = root.appendingPathComponent("unstaged.txt")
        try "base staged\n".write(to: staged, atomically: true, encoding: .utf8)
        try "base unstaged\n".write(to: unstaged, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "staged.txt").ok)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "unstaged.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "add transfer fixtures").ok)

        try "staged change\n".write(to: staged, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "staged.txt").ok)
        try "unstaged change\n".write(to: unstaged, atomically: true, encoding: .utf8)
        try "untracked\n".write(
            to: root.appendingPathComponent("notes.txt"),
            atomically: true,
            encoding: .utf8
        )

        let name = "managed-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let result = GitToolExecutor().createWorktree(cwd: root, path: name, base: "HEAD", managed: true)
        defer { _ = GitToolExecutor().removeWorktree(cwd: root, path: name, force: true) }

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(currentBranchName(in: target), "", "managed task worktrees start detached")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("staged.txt")), "staged change\n")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("unstaged.txt")), "unstaged change\n")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("notes.txt")), "untracked\n")
        let status = GitToolExecutor().status(cwd: target)
        XCTAssertTrue(status.stdout.contains("M  staged.txt"), status.stdout)
        XCTAssertTrue(status.stdout.contains(" M unstaged.txt"), status.stdout)
        XCTAssertTrue(status.stdout.contains("?? notes.txt"), status.stdout)
    }

    func testManagedCreateCopiesOnlyIncludedIgnoredFilesAndAgentsOverride() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        try ".env\nignored/\nAGENTS.override.md\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try ".env\nignored/config.json\nignored/link\n".write(
            to: root.appendingPathComponent(".worktreeinclude"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: ".gitignore").ok)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: ".worktreeinclude").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "configure managed worktrees").ok)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("ignored"),
            withIntermediateDirectories: true
        )
        try "TOKEN=local\n".write(
            to: root.appendingPathComponent(".env"),
            atomically: true,
            encoding: .utf8
        )
        try "{}\n".write(
            to: root.appendingPathComponent("ignored/config.json"),
            atomically: true,
            encoding: .utf8
        )
        try "do not copy\n".write(
            to: root.appendingPathComponent("ignored/not-included.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "local instructions\n".write(
            to: root.appendingPathComponent("AGENTS.override.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("ignored/link"),
            withDestinationURL: root.appendingPathComponent(".env")
        )

        let name = "managed-includes-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let result = GitToolExecutor().createWorktree(cwd: root, path: name, managed: true)
        defer { _ = GitToolExecutor().removeWorktree(cwd: root, path: name, force: true) }

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent(".env").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("ignored/config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("AGENTS.override.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("ignored/not-included.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent("ignored/link").path))
        XCTAssertTrue(result.stdout.contains("Skipped 1 local symlink"), result.stdout)
    }

    func testManagedCreateRollsBackWhenLocalFileWouldOverwriteBaseContent() throws {
        let root = try makeTempGitRepoWithInitialCommit()
        let collision = root.appendingPathComponent("collision.txt")
        try "tracked in old base\n".write(to: collision, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "collision.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "add collision").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git tag collision-base", cwd: root)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git rm collision.txt", cwd: root)).ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "remove collision").ok)
        try "untracked current file\n".write(to: collision, atomically: true, encoding: .utf8)

        let name = "managed-rollback-\(UUID().uuidString)"
        let target = root.deletingLastPathComponent().appendingPathComponent(name)
        let result = GitToolExecutor().createWorktree(cwd: root, path: name, base: "collision-base", managed: true)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("refused to overwrite") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(GitToolExecutor().listWorktrees(cwd: root).stdout.contains(target.path))
    }

    func testManagedCreateRejectsBranchCreation() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        let result = GitToolExecutor().createWorktree(
            cwd: root,
            path: "managed-branch",
            branch: "feature/not-detached",
            managed: true
        )

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Managed worktrees start detached and cannot create a branch.")
    }

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
