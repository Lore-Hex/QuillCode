import Foundation
import XCTest
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceManagedWorktreeRetentionIntegrationTests: XCTestCase {
    func testEnforcementSnapshotsAndRemovesOldestExcessWorktrees() throws {
        let fixture = try RetentionFixture(count: 4, retentionLimit: 2)
        defer { fixture.remove() }
        let model = fixture.model(selectedThreadID: fixture.threads.last?.id)

        XCTAssertEqual(model.enforceManagedWorktreeRetention(), 2)

        for thread in fixture.threads.prefix(2) {
            let retained = try XCTUnwrap(model.root.threads.first { $0.id == thread.id })
            XCTAssertNotNil(retained.worktree?.snapshot)
            XCTAssertFalse(FileManager.default.fileExists(atPath: thread.worktree?.path ?? ""))
            XCTAssertNotNil(try fixture.threadStore.load(thread.id).worktree?.snapshot)
        }
        for thread in fixture.threads.suffix(2) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: thread.worktree?.path ?? ""))
            XCTAssertNil(model.root.threads.first { $0.id == thread.id }?.worktree?.snapshot)
        }
    }

    func testDisabledCleanupLeavesEveryCheckoutInPlace() throws {
        let fixture = try RetentionFixture(count: 3, retentionLimit: 1, cleanupEnabled: false)
        defer { fixture.remove() }
        let model = fixture.model(selectedThreadID: fixture.threads.last?.id)

        XCTAssertEqual(model.enforceManagedWorktreeRetention(), 0)
        XCTAssertTrue(fixture.threads.allSatisfy {
            FileManager.default.fileExists(atPath: $0.worktree?.path ?? "")
        })
    }

    func testSwitchingThreadsMakesOutgoingCheckoutEligible() throws {
        let fixture = try RetentionFixture(count: 2, retentionLimit: 1)
        defer { fixture.remove() }
        let oldest = try XCTUnwrap(fixture.threads.first)
        let newest = try XCTUnwrap(fixture.threads.last)
        let model = fixture.model(selectedThreadID: oldest.id)

        model.selectThread(newest.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oldest.worktree?.path ?? ""))
        XCTAssertNotNil(model.root.threads.first { $0.id == oldest.id }?.worktree?.snapshot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: newest.worktree?.path ?? ""))
    }
}

private final class RetentionFixture {
    let container: URL
    let repository: URL
    let managedRoot: URL
    let snapshotDirectory: URL
    let project: ProjectRef
    let threads: [ChatThread]
    let threadStore: JSONThreadStore
    let settings: ManagedWorktreeSettings

    init(count: Int, retentionLimit: Int, cleanupEnabled: Bool = true) throws {
        container = FileManager.default.temporaryDirectory
            .appendingPathComponent("retention-integration-\(UUID().uuidString)")
        repository = container.appendingPathComponent("repo")
        managedRoot = container.appendingPathComponent("managed-worktrees")
        snapshotDirectory = container.appendingPathComponent("snapshots")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try initializeGitRepository(at: repository)
        try "# Retention fixture\n".write(
            to: repository.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        _ = try runGit(["add", "README.md"], cwd: repository)
        _ = try runGit(["commit", "-m", "initial"], cwd: repository)

        project = ProjectRef(name: "Repo", path: repository.path)
        threadStore = JSONThreadStore(directory: container.appendingPathComponent("threads"))
        settings = ManagedWorktreeSettings(
            rootPath: managedRoot.path,
            automaticCleanupEnabled: cleanupEnabled,
            retentionLimit: retentionLimit
        )
        let git = GitToolExecutor(managedWorktreeRoot: managedRoot)
        var created: [ChatThread] = []
        for index in 0..<count {
            let path = managedRoot.appendingPathComponent("task-\(index)")
            let result = git.createWorktree(cwd: repository, path: path.path, managed: true)
            guard result.ok else {
                throw NSError(
                    domain: "QuillCodeRetentionFixture",
                    code: index,
                    userInfo: [NSLocalizedDescriptionKey: result.error ?? result.stderr]
                )
            }
            try "task \(index)\n".write(
                to: path.appendingPathComponent("task-note.txt"),
                atomically: true,
                encoding: .utf8
            )
            var thread = ChatThread(
                title: "Task \(index)",
                projectID: project.id,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            thread.worktree = WorktreeBinding(
                path: path.path,
                branch: "",
                base: "main",
                managedRoot: managedRoot.path
            )
            try threadStore.save(thread)
            created.append(thread)
        }
        threads = created
    }

    @MainActor
    func model(selectedThreadID: UUID?) -> QuillCodeWorkspaceModel {
        QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                config: AppConfig(managedWorktrees: settings),
                projects: [project],
                selectedProjectID: project.id,
                threads: threads,
                selectedThreadID: selectedThreadID
            ),
            threadStore: threadStore,
            worktreeSnapshotStore: ManagedWorktreeSnapshotStore(directory: snapshotDirectory),
            managedWorktreeDefaultRoot: managedRoot
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: container)
    }
}
