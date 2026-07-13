import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ManagedWorktreeRetentionPlannerTests: XCTestCase {
    func testSelectsOldestEligibleExcessWorktrees() throws {
        let fixture = try Fixture(count: 5)
        defer { fixture.remove() }
        var threads = fixture.threads
        threads[0].isPinned = true
        let selected = threads[1].id
        let running = threads[2].id

        let plan = ManagedWorktreeRetentionPlanner.plan(
            threads: threads,
            selectedThreadID: selected,
            runningThreadIDs: [running],
            settings: ManagedWorktreeSettings(retentionLimit: 2)
        )

        XCTAssertEqual(plan.activeManagedWorktreeCount, 5)
        XCTAssertEqual(plan.targetRemovalCount, 3)
        XCTAssertEqual(plan.candidateThreadIDs, [threads[3].id, threads[4].id])
    }

    func testDisabledCleanupPlansNoWork() throws {
        let fixture = try Fixture(count: 2)
        defer { fixture.remove() }

        let plan = ManagedWorktreeRetentionPlanner.plan(
            threads: fixture.threads,
            selectedThreadID: nil,
            runningThreadIDs: [],
            settings: ManagedWorktreeSettings(automaticCleanupEnabled: false, retentionLimit: 1)
        )

        XCTAssertEqual(plan.activeManagedWorktreeCount, 0)
        XCTAssertEqual(plan.targetRemovalCount, 0)
        XCTAssertEqual(plan.candidateThreadIDs, [])
    }

    func testIgnoresLocalNamedMissingAndAlreadySnapshottedBindings() throws {
        let fixture = try Fixture(count: 5)
        defer { fixture.remove() }
        var threads = fixture.threads
        threads[0].worktree?.location = .local
        threads[1].worktree?.branch = "feature/permanent"
        threads[2].worktree?.path += "-missing"
        threads[3].worktree?.snapshot = WorktreeSnapshotReference(
            headCommit: String(repeating: "a", count: 40),
            fileCount: 1,
            byteCount: 10
        )

        let plan = ManagedWorktreeRetentionPlanner.plan(
            threads: threads,
            selectedThreadID: nil,
            runningThreadIDs: [],
            settings: ManagedWorktreeSettings(retentionLimit: 1)
        )

        XCTAssertEqual(plan.activeManagedWorktreeCount, 2)
        XCTAssertEqual(plan.targetRemovalCount, 1)
        XCTAssertEqual(plan.candidateThreadIDs, [threads[4].id])
    }
}

private final class Fixture {
    let root: URL
    var threads: [ChatThread]

    init(count: Int) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("retention-planner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let threads = try (0..<count).map { index in
            let worktree = root.appendingPathComponent("task-\(index)")
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
            var thread = ChatThread(
                title: "Task \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            thread.worktree = WorktreeBinding(path: worktree.path, branch: "", managedRoot: root.path)
            return thread
        }
        self.root = root
        self.threads = threads
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
