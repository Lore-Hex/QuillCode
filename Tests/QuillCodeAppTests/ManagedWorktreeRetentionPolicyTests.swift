import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ManagedWorktreeRetentionPolicyTests: XCTestCase {
    func testRemovesOldestEligibleWorktreeToMeetLimit() {
        let threads = [
            thread(path: "/work/old", age: 10),
            thread(path: "/work/middle", age: 20),
            thread(path: "/work/new", age: 30)
        ]

        let candidates = ManagedWorktreeRetentionPolicy.removalCandidates(
            threads: threads,
            runningThreadIDs: [],
            selectedThreadID: nil,
            retentionLimit: 2,
            pathExists: { _ in true }
        )

        XCTAssertEqual(candidates, [threads[0].id])
    }

    func testProtectsPinnedRunningSelectedAndPermanentWorktrees() {
        var pinned = thread(path: "/work/pinned", age: 60)
        pinned.isPinned = true
        let running = thread(path: "/work/running", age: 50)
        let selected = thread(path: "/work/selected", age: 40)
        var branched = thread(path: "/work/branched", age: 30)
        branched.worktree?.branch = "feature/keep"
        var local = thread(path: "/work/local", age: 20)
        local.worktree?.location = .local
        let removable = thread(path: "/work/removable", age: 10)

        let candidates = ManagedWorktreeRetentionPolicy.removalCandidates(
            threads: [pinned, running, selected, branched, local, removable],
            runningThreadIDs: [running.id],
            selectedThreadID: selected.id,
            retentionLimit: 1,
            pathExists: { _ in true }
        )

        XCTAssertEqual(candidates, [removable.id])
    }

    func testDuplicatePathFailsClosed() {
        let first = thread(path: "/work/shared", age: 20)
        let second = thread(path: "/work/shared/../shared", age: 10)
        let unique = thread(path: "/work/unique", age: 5)

        XCTAssertEqual(
            ManagedWorktreeRetentionPolicy.removalCandidates(
                threads: [first, second, unique],
                runningThreadIDs: [],
                selectedThreadID: nil,
                retentionLimit: 1,
                pathExists: { _ in true }
            ),
            [unique.id]
        )
    }

    func testDisabledCleanupAndMissingPathsProduceNoCandidates() {
        let existing = thread(path: "/work/existing", age: 20)
        let missing = thread(path: "/work/missing", age: 10)

        XCTAssertTrue(ManagedWorktreeRetentionPolicy.removalCandidates(
            threads: [existing],
            runningThreadIDs: [],
            selectedThreadID: nil,
            retentionLimit: nil,
            pathExists: { _ in true }
        ).isEmpty)
        XCTAssertTrue(ManagedWorktreeRetentionPolicy.removalCandidates(
            threads: [existing, missing],
            runningThreadIDs: [],
            selectedThreadID: nil,
            retentionLimit: 1,
            pathExists: { $0 == existing.worktree?.path }
        ).isEmpty)
    }

    private func thread(path: String, age: TimeInterval) -> ChatThread {
        ChatThread(
            title: path,
            updatedAt: Date(timeIntervalSince1970: age),
            worktree: WorktreeBinding(path: path, branch: "")
        )
    }
}
