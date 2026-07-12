import XCTest
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceManagedWorktreeSnapshotIntegrationTests: XCTestCase {
    func testArchivePersistsSnapshotRemovesWorktreeAndCommandRestoresIt() throws {
        let fixture = try makeFixture()
        try "task note\n".write(
            to: fixture.worktree.appendingPathComponent("task-note.txt"),
            atomically: true,
            encoding: .utf8
        )
        let model = fixture.model()

        XCTAssertTrue(model.archiveThread(fixture.thread.id))

        let archived = try XCTUnwrap(model.root.threads.first { $0.id == fixture.thread.id })
        let reference = try XCTUnwrap(archived.worktree?.snapshot)
        XCTAssertTrue(archived.isArchived)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.worktree.path))
        XCTAssertEqual(try fixture.threadStore.load(fixture.thread.id).worktree?.snapshot, reference)

        XCTAssertTrue(model.unarchiveThread(fixture.thread.id))
        XCTAssertTrue(model.runWorkspaceCommand(
            WorkspaceCommandAction.threadRestoreWorktree.rawValue,
            workspaceRoot: fixture.root
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktree.path))
        XCTAssertEqual(
            try String(contentsOf: fixture.worktree.appendingPathComponent("task-note.txt"), encoding: .utf8),
            "task note\n"
        )
        XCTAssertNil(model.selectedThread?.worktree?.snapshot)
        XCTAssertNil(try fixture.threadStore.load(fixture.thread.id).worktree?.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.snapshotDirectory
                .appendingPathComponent(reference.id.uuidString.lowercased()).path
        ))
    }

    func testPinnedManagedTaskArchivesWithoutRemovingWorktree() throws {
        var fixture = try makeFixture()
        fixture.thread.isPinned = true
        try fixture.threadStore.save(fixture.thread)
        let model = fixture.model()

        XCTAssertTrue(model.archiveThread(fixture.thread.id))

        let archived = try XCTUnwrap(model.root.threads.first { $0.id == fixture.thread.id })
        XCTAssertTrue(archived.isArchived)
        XCTAssertTrue(archived.isPinned)
        XCTAssertNil(archived.worktree?.snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    func testRunningManagedTaskArchivesWithoutRemovingWorktree() throws {
        let fixture = try makeFixture()
        let model = fixture.model(
            agentRuns: WorkspaceAgentRunRegistry(
                statusesByThreadID: [fixture.thread.id: "Running"]
            )
        )

        XCTAssertTrue(model.archiveThread(fixture.thread.id))

        let archived = try XCTUnwrap(model.root.threads.first { $0.id == fixture.thread.id })
        XCTAssertNil(archived.worktree?.snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    func testNamedBranchTaskArchivesWithoutRemovingPermanentWorktree() throws {
        var fixture = try makeFixture()
        let branch = "feature/permanent-\(UUID().uuidString.prefix(8))"
        let branchResult = fixture.git.createWorktreeBranch(cwd: fixture.worktree, branch: branch)
        XCTAssertTrue(branchResult.ok, "\(branchResult.error ?? "") \(branchResult.stderr)")
        fixture.thread.worktree?.branch = branch
        try fixture.threadStore.save(fixture.thread)
        let model = fixture.model()

        XCTAssertTrue(model.archiveThread(fixture.thread.id))

        let archived = try XCTUnwrap(model.root.threads.first { $0.id == fixture.thread.id })
        XCTAssertNil(archived.worktree?.snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    func testBulkArchiveUsesSameSnapshotLifecycle() throws {
        let fixture = try makeFixture()
        let model = fixture.model()
        model.startSidebarSelection(selecting: fixture.thread.id)

        XCTAssertTrue(model.performSidebarBulkAction(.archive))

        let archived = try XCTUnwrap(model.root.threads.first { $0.id == fixture.thread.id })
        XCTAssertTrue(archived.isArchived)
        XCTAssertNotNil(archived.worktree?.snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.worktree.path))
    }

    func testDeletingArchivedTaskRemovesItsSavedSnapshot() throws {
        let fixture = try makeFixture()
        let model = fixture.model()
        XCTAssertTrue(model.archiveThread(fixture.thread.id))
        let reference = try XCTUnwrap(model.root.threads.first?.worktree?.snapshot)
        let snapshotPath = fixture.snapshotDirectory
            .appendingPathComponent(reference.id.uuidString.lowercased()).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotPath))

        XCTAssertTrue(model.deleteThread(fixture.thread.id))

        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotPath))
    }

    func testSnapshotFailureArchivesThreadButKeepsCheckout() throws {
        var fixture = try makeFixture()
        let unregisteredDirectory = try makeTempDirectory()
        fixture.thread.worktree?.path = unregisteredDirectory.path
        try fixture.threadStore.save(fixture.thread)
        let model = fixture.model()

        XCTAssertTrue(model.archiveThread(fixture.thread.id))

        let archived = try XCTUnwrap(model.root.threads.first)
        XCTAssertTrue(archived.isArchived)
        XCTAssertNil(archived.worktree?.snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unregisteredDirectory.path))
        XCTAssertTrue(model.lastError?.contains("worktree was kept") == true, model.lastError ?? "")
    }

    private func makeFixture() throws -> ManagedArchiveFixture {
        let root = try makeTempGitRepoWithInitialCommit()
        let name = "archive-\(UUID().uuidString)"
        let worktree = root.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
        let git = GitToolExecutor()
        let create = git.createWorktree(cwd: root, path: name, managed: true)
        XCTAssertTrue(create.ok, "\(create.error ?? "") \(create.stderr)")
        let project = ProjectRef(name: "Repo", path: root.path)
        var thread = ChatThread(title: "Managed task", projectID: project.id)
        thread.worktree = WorktreeBinding(path: worktree.path, branch: "", base: "main")
        let persistenceRoot = try makeTempDirectory()
        let threadStore = JSONThreadStore(directory: persistenceRoot.appendingPathComponent("threads"))
        try threadStore.save(thread)
        return ManagedArchiveFixture(
            root: root,
            worktree: worktree,
            snapshotDirectory: persistenceRoot.appendingPathComponent("snapshots"),
            project: project,
            thread: thread,
            threadStore: threadStore,
            git: git
        )
    }
}

private struct ManagedArchiveFixture {
    let root: URL
    let worktree: URL
    let snapshotDirectory: URL
    let project: ProjectRef
    var thread: ChatThread
    let threadStore: JSONThreadStore
    let git: GitToolExecutor

    @MainActor
    func model(
        agentRuns: WorkspaceAgentRunRegistry = WorkspaceAgentRunRegistry()
    ) -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [thread],
                selectedThreadID: thread.id
            ),
            agentRuns: agentRuns,
            threadStore: threadStore,
            worktreeSnapshotStore: ManagedWorktreeSnapshotStore(directory: snapshotDirectory)
        )
    }
}
