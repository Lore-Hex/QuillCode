import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class ManagedWorktreeSnapshotStoreTests: XCTestCase {
    func testCaptureRemoveAndRestorePreservesExactTaskState() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        try addTaskChanges(to: fixture.worktree)
        let store = ManagedWorktreeSnapshotStore(directory: fixture.snapshotDirectory)
        let threadID = UUID()

        let reference = try store.capture(threadID: threadID, binding: fixture.binding)
        var archivedBinding = fixture.binding
        archivedBinding.snapshot = reference
        let removal = fixture.git.removeWorktree(
            cwd: fixture.root,
            path: fixture.worktree.lastPathComponent,
            force: true
        )

        XCTAssertTrue(removal.ok, "\(removal.error ?? "") \(removal.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.worktree.path))
        XCTAssertTrue(archivedBinding.canRestoreSnapshot)

        let restored = try store.restore(
            threadID: threadID,
            reference: reference,
            binding: archivedBinding,
            projectRoot: fixture.root
        )

        XCTAssertEqual(restored.path, fixture.worktree.path)
        XCTAssertEqual(restored.restoredFileCount, 1)
        XCTAssertEqual(try text("staged.txt", in: fixture.worktree), "staged task change\n")
        XCTAssertEqual(try text("unstaged.txt", in: fixture.worktree), "unstaged task change\n")
        XCTAssertEqual(try text("notes/task.txt", in: fixture.worktree), "untracked task note\n")
        XCTAssertEqual(
            gitStatus(in: fixture.worktree),
            "M  staged.txt\n M unstaged.txt\n?? notes/task.txt\n"
        )
        XCTAssertEqual(currentCommit(in: fixture.worktree), reference.headCommit)
    }

    func testRestoreUsesCapturedCommitAfterMainAdvances() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        try addTaskChanges(to: fixture.worktree)
        let store = ManagedWorktreeSnapshotStore(directory: fixture.snapshotDirectory)
        let threadID = UUID()
        let reference = try store.capture(threadID: threadID, binding: fixture.binding)
        var archivedBinding = fixture.binding
        archivedBinding.snapshot = reference
        XCTAssertTrue(fixture.git.removeWorktree(
            cwd: fixture.root,
            path: fixture.worktree.lastPathComponent,
            force: true
        ).ok)
        try "newer main\n".write(
            to: fixture.root.appendingPathComponent("newer-main.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(fixture.git.stage(cwd: fixture.root, path: "newer-main.txt").ok)
        XCTAssertTrue(fixture.git.commit(cwd: fixture.root, message: "advance main").ok)

        _ = try store.restore(
            threadID: threadID,
            reference: reference,
            binding: archivedBinding,
            projectRoot: fixture.root
        )

        XCTAssertEqual(currentCommit(in: fixture.worktree), reference.headCommit)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.worktree.appendingPathComponent("newer-main.txt").path
        ))
    }

    func testRestoreRejectsDifferentRepository() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let store = ManagedWorktreeSnapshotStore(directory: fixture.snapshotDirectory)
        let threadID = UUID()
        let reference = try store.capture(threadID: threadID, binding: fixture.binding)
        var archivedBinding = fixture.binding
        archivedBinding.snapshot = reference
        XCTAssertTrue(fixture.git.removeWorktree(
            cwd: fixture.root,
            path: fixture.worktree.lastPathComponent,
            force: true
        ).ok)
        let otherRepository = try makeTempGitRepoWithInitialCommit()

        XCTAssertThrowsError(try store.restore(
            threadID: UUID(),
            reference: reference,
            binding: archivedBinding,
            projectRoot: fixture.root
        )) { error in
            guard case .snapshotCorrupt(let detail) = error as? ManagedWorktreeSnapshotError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(detail.contains("different task"), detail)
        }

        XCTAssertThrowsError(try store.restore(
            threadID: threadID,
            reference: reference,
            binding: archivedBinding,
            projectRoot: otherRepository
        )) { error in
            XCTAssertEqual(error as? ManagedWorktreeSnapshotError, .repositoryMismatch)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    func testCaptureRejectsNamedPermanentWorktree() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let permanent = WorktreeBinding(
            path: fixture.binding.path,
            branch: "feature/permanent",
            base: fixture.binding.base
        )

        XCTAssertThrowsError(try ManagedWorktreeSnapshotStore(
            directory: fixture.snapshotDirectory
        ).capture(threadID: UUID(), binding: permanent)) { error in
            guard case .invalidBinding = error as? ManagedWorktreeSnapshotError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRemoveIfUnchangedRejectsConcurrentMutationAndKeepsWorktree() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let store = ManagedWorktreeSnapshotStore(directory: fixture.snapshotDirectory)
        let threadID = UUID()
        let reference = try store.capture(threadID: threadID, binding: fixture.binding)
        var capturedBinding = fixture.binding
        capturedBinding.snapshot = reference
        try "changed after capture\n".write(
            to: fixture.worktree.appendingPathComponent("unstaged.txt"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try store.removeIfUnchanged(
            threadID: threadID,
            reference: reference,
            binding: capturedBinding,
            projectRoot: fixture.root
        )) { error in
            XCTAssertEqual(error as? ManagedWorktreeSnapshotError, .sourceChanged)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktree.path))
        XCTAssertTrue(fixture.git.listWorktrees(cwd: fixture.root).stdout.contains(fixture.worktree.path))
    }

    func testRemoveIfUnchangedRemovesAnExactCapturedWorktree() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        try addTaskChanges(to: fixture.worktree)
        let store = ManagedWorktreeSnapshotStore(directory: fixture.snapshotDirectory)
        let threadID = UUID()
        let reference = try store.capture(threadID: threadID, binding: fixture.binding)
        var capturedBinding = fixture.binding
        capturedBinding.snapshot = reference

        try store.removeIfUnchanged(
            threadID: threadID,
            reference: reference,
            binding: capturedBinding,
            projectRoot: fixture.root
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.worktree.path))
        XCTAssertFalse(fixture.git.listWorktrees(cwd: fixture.root).stdout.contains(fixture.worktree.path))
    }

    func testCorruptPatchRollsBackCreatedWorktree() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        try "staged change\n".write(
            to: fixture.worktree.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(fixture.git.stage(cwd: fixture.worktree, path: "staged.txt").ok)
        let store = ManagedWorktreeSnapshotStore(directory: fixture.snapshotDirectory)
        let threadID = UUID()
        let reference = try store.capture(threadID: threadID, binding: fixture.binding)
        var archivedBinding = fixture.binding
        archivedBinding.snapshot = reference
        XCTAssertTrue(fixture.git.removeWorktree(
            cwd: fixture.root,
            path: fixture.worktree.lastPathComponent,
            force: true
        ).ok)
        let patchURL = fixture.snapshotDirectory
            .appendingPathComponent(reference.id.uuidString.lowercased())
            .appendingPathComponent("staged.patch")
        let patchSize = try XCTUnwrap(try patchURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try Data(repeating: 0x78, count: patchSize).write(to: patchURL)

        XCTAssertThrowsError(try store.restore(
            threadID: threadID,
            reference: reference,
            binding: archivedBinding,
            projectRoot: fixture.root
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.worktree.path))
        let listed = fixture.git.listWorktrees(cwd: fixture.root)
        XCTAssertFalse(listed.stdout.contains(fixture.worktree.path), listed.stdout)
    }

    private func makeFixture() throws -> SnapshotFixture {
        let root = try makeTempGitRepoWithInitialCommit()
        try "base staged\n".write(
            to: root.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "base unstaged\n".write(
            to: root.appendingPathComponent("unstaged.txt"),
            atomically: true,
            encoding: .utf8
        )
        let git = GitToolExecutor()
        XCTAssertTrue(git.stage(cwd: root, path: "staged.txt").ok)
        XCTAssertTrue(git.stage(cwd: root, path: "unstaged.txt").ok)
        XCTAssertTrue(git.commit(cwd: root, message: "add snapshot fixtures").ok)
        let name = "snapshot-\(UUID().uuidString)"
        let worktree = root.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        let create = git.createWorktree(cwd: root, path: name, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        return SnapshotFixture(
            root: root,
            worktree: worktree,
            snapshotDirectory: root.deletingLastPathComponent().appendingPathComponent("snapshots-\(UUID().uuidString)"),
            binding: WorktreeBinding(path: worktree.path, branch: "", base: "main"),
            git: git
        )
    }

    private func addTaskChanges(to root: URL) throws {
        try "staged task change\n".write(
            to: root.appendingPathComponent("staged.txt"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "staged.txt").ok)
        try "unstaged task change\n".write(
            to: root.appendingPathComponent("unstaged.txt"),
            atomically: true,
            encoding: .utf8
        )
        let notes = root.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: notes, withIntermediateDirectories: true)
        try "untracked task note\n".write(
            to: notes.appendingPathComponent("task.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func text(_ path: String, in root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func gitStatus(in root: URL) -> String {
        let result = GitProcessRunner().runGit(
            ["status", "--porcelain=v1", "--untracked-files=all"],
            cwd: root,
            timeoutSeconds: 15
        )
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        return result.stdout
    }

    private func currentCommit(in root: URL) -> String {
        let result = GitProcessRunner().runGit(
            ["rev-parse", "HEAD"],
            cwd: root,
            timeoutSeconds: 15
        )
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SnapshotFixture {
    let root: URL
    let worktree: URL
    let snapshotDirectory: URL
    let binding: WorktreeBinding
    let git: GitToolExecutor

    var container: URL { root.deletingLastPathComponent() }
}
