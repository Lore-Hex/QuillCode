import XCTest
@testable import QuillCodeTools

final class GitLocalToolExecutorTests: XCTestCase {
    func testStageStagesWorkspaceFileWithSpaces() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello world.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)

        let result = GitToolExecutor().stage(cwd: root, path: "hello world.txt")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let status = GitToolExecutor().status(cwd: root)
        XCTAssertTrue(status.stdout.contains("A  "), status.stdout)
        XCTAssertTrue(status.stdout.contains("hello world.txt"), status.stdout)
    }

    func testRestoreRestoresTrackedWorkspaceFile() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "before\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "after\n".write(to: file, atomically: true, encoding: .utf8)

        let result = GitToolExecutor().restore(cwd: root, path: "hello.txt")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "before\n")
    }

    func testStageAndRestoreRejectOutsideWorkspacePaths() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let git = GitToolExecutor()

        let stage = git.stage(cwd: root, path: "../escape.txt")
        let restore = git.restore(cwd: root, path: "../escape.txt")

        XCTAssertFalse(stage.ok)
        XCTAssertTrue(stage.error?.contains("outside the workspace") == true, stage.error ?? "")
        XCTAssertFalse(restore.ok)
        XCTAssertTrue(restore.error?.contains("outside the workspace") == true, restore.error ?? "")
    }

    func testStageAndRestoreRejectSymlinkEscapePaths() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let git = GitToolExecutor()

        // `escape/secret.txt` is lexically in-workspace but resolves outside via the symlink — the
        // shared symlink-resolved boundary must reject it (not just a lexical `..` check).
        let stage = git.stage(cwd: root, path: "escape/secret.txt")
        let restore = git.restore(cwd: root, path: "escape/secret.txt")

        XCTAssertFalse(stage.ok)
        XCTAssertTrue(stage.error?.contains("outside the workspace") == true, stage.error ?? "")
        XCTAssertFalse(restore.ok)
        XCTAssertTrue(restore.error?.contains("outside the workspace") == true, restore.error ?? "")
    }

    func testCommitCommitsStagedChanges() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)

        let result = GitToolExecutor().commit(cwd: root, message: "Add hello file")

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let log = ShellToolExecutor().run(.init(command: "git log -1 --pretty=%s", cwd: root))
        XCTAssertEqual(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Add hello file")
        XCTAssertFalse(GitToolExecutor().status(cwd: root).stdout.contains("hello.txt"))
    }

    func testLocalExecutorStagesRestoresAndCommitsTrackedFiles() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        let git = GitLocalToolExecutor()

        try "before\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(git.stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(git.commit(cwd: root, message: "Add hello").ok)
        try "after\n".write(to: file, atomically: true, encoding: .utf8)

        let restore = git.restore(cwd: root, path: "hello.txt")

        XCTAssertTrue(restore.ok, "\(restore.error ?? "") \(restore.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "before\n")
    }

    func testCommitRejectsEmptyMessage() throws {
        let result = GitToolExecutor().commit(cwd: try makeTempDirectory(), message: " ")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("message is required") == true, result.error ?? "")
    }

    func testPushPushesCurrentBranchToNamedRemote() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        let remote = parent.appendingPathComponent("remote.git")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try initializeGitRepo(at: root)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git init --bare '\(remote.path)'", cwd: parent)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git remote add origin '\(remote.path)'", cwd: root)).ok)
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(GitToolExecutor().commit(cwd: root, message: "Add hello").ok)
        let branch = currentBranchName(in: root)

        let result = GitToolExecutor().push(cwd: root, remote: "origin", branch: branch, setUpstream: true)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        let remoteHead = ShellToolExecutor().run(.init(
            command: "git --git-dir='\(remote.path)' rev-parse \(branch)",
            cwd: parent
        ))
        XCTAssertTrue(remoteHead.ok, "\(remoteHead.error ?? "") \(remoteHead.stderr)")
        XCTAssertFalse(remoteHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testFetchFetchesNamedRemote() throws {
        let parent = try makeTempDirectory()
        let remote = parent.appendingPathComponent("remote.git")
        let root = parent.appendingPathComponent("repo")
        try initializeBareRemote(remote, parent: parent)
        try cloneRemote(remote, into: root, parent: parent)

        let result = GitToolExecutor().fetch(cwd: root, remote: "origin", prune: true)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }

    func testPullUsesFastForwardByDefault() throws {
        let parent = try makeTempDirectory()
        let remote = parent.appendingPathComponent("remote.git")
        let seed = parent.appendingPathComponent("seed")
        let root = parent.appendingPathComponent("repo")
        try initializeBareRemote(remote, parent: parent)
        try cloneRemote(remote, into: seed, parent: parent)
        try makeCommit(in: seed, file: "hello.txt", contents: "hello\n", message: "seed")
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git push origin HEAD:main", cwd: seed)).ok)
        try cloneRemote(remote, into: root, parent: parent)
        try makeCommit(in: seed, file: "hello.txt", contents: "hello again\n", message: "update")
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git push origin HEAD:main", cwd: seed)).ok)

        let result = GitToolExecutor().pull(cwd: root)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8),
            "hello again\n"
        )
    }

    func testPushRejectsUnsafeRemoteAndBranchNames() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        XCTAssertFalse(GitToolExecutor().push(cwd: root, remote: "--all").ok)
        XCTAssertFalse(GitToolExecutor().push(cwd: root, remote: "origin", branch: "feature;rm").ok)
    }

    func testFetchAndPullRejectUnsafeRemoteAndBranchNames() throws {
        let root = try makeTempGitRepoWithInitialCommit()

        XCTAssertFalse(GitToolExecutor().fetch(cwd: root, remote: "--all").ok)
        XCTAssertFalse(GitToolExecutor().pull(cwd: root, remote: "origin", branch: "feature;rm").ok)
    }

    func testInputValidatorNormalizesSharedGitInputs() throws {
        let root = try makeTempDirectory()

        XCTAssertNil(GitInputValidator.trimmedNonEmpty("  \n"))
        XCTAssertEqual(GitInputValidator.trimmedNonEmpty("  origin/main  "), "origin/main")
        XCTAssertEqual(try GitInputValidator.safeName(" feature/quill "), "feature/quill")
        XCTAssertEqual(try GitInputValidator.safeRelativePath("notes/todo.txt", cwd: root), "notes/todo.txt")
        XCTAssertEqual(try GitInputValidator.safeRelativePath(root.path, cwd: root), ".")

        XCTAssertThrowsError(try GitInputValidator.safeName("--bad"))
        XCTAssertThrowsError(try GitInputValidator.safeName("../main"))
        XCTAssertThrowsError(try GitInputValidator.safeRelativePath("../outside", cwd: root))
    }

    private func initializeBareRemote(_ remote: URL, parent: URL) throws {
        let result = ShellToolExecutor().run(.init(command: "git init --bare '\(remote.path)'", cwd: parent))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
    }

    private func cloneRemote(_ remote: URL, into root: URL, parent: URL) throws {
        let result = ShellToolExecutor().run(.init(command: "git clone '\(remote.path)' '\(root.path)'", cwd: parent))
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git config user.email quillcode-tests@example.com", cwd: root)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git config user.name 'QuillCode Tests'", cwd: root)).ok)
        _ = ShellToolExecutor().run(.init(command: "git checkout -B main", cwd: root))
    }

    private func makeCommit(in root: URL, file: String, contents: String, message: String) throws {
        try contents.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git add -- '\(file)'", cwd: root)).ok)
        let commit = ShellToolExecutor().run(.init(command: "git commit -m '\(message)'", cwd: root))
        XCTAssertTrue(commit.ok, "\(commit.error ?? "") \(commit.stderr)")
    }
}
