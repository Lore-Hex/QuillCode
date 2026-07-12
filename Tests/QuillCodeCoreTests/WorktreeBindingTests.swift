import XCTest
import Foundation
@testable import QuillCodeCore

final class WorktreeBindingTests: XCTestCase {
    private func encodeDecode(_ thread: ChatThread) throws -> ChatThread {
        let data = try JSONEncoder().encode(thread)
        return try JSONDecoder().decode(ChatThread.self, from: data)
    }

    func testBindingRoundTrips() throws {
        var thread = ChatThread(title: "T")
        thread.worktree = WorktreeBinding(path: "/tmp/wt", branch: "feature/x", base: "main")
        thread.forkParentThreadID = UUID()
        thread.forkAnchorTurnMessageID = UUID()
        let decoded = try encodeDecode(thread)
        XCTAssertEqual(decoded.worktree, thread.worktree)
        XCTAssertEqual(decoded.forkParentThreadID, thread.forkParentThreadID)
        XCTAssertEqual(decoded.forkAnchorTurnMessageID, thread.forkAnchorTurnMessageID)
    }

    func testLegacyBindingWithoutLocationDefaultsToWorktree() throws {
        let legacy = #"{"path":"/tmp/wt","branch":"","base":"main"}"#

        let binding = try JSONDecoder().decode(
            WorktreeBinding.self,
            from: Data(legacy.utf8)
        )

        XCTAssertEqual(binding.location, .worktree)
        XCTAssertNil(binding.snapshot)
    }

    func testExplicitLocationRoundTrips() throws {
        let binding = WorktreeBinding(
            path: "/tmp/wt",
            branch: "",
            base: "main",
            location: .local
        )

        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(WorktreeBinding.self, from: data)

        XCTAssertEqual(decoded, binding)
        XCTAssertEqual(decoded.location, .local)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""location":"local""#))
    }

    func testEncodesNoWorktreeKeysWhenNil() throws {
        let data = try JSONEncoder().encode(ChatThread(title: "T"))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("worktree"), json)
        XCTAssertFalse(json.contains("forkParentThreadID"), json)
    }

    func testDecodesLegacyJSONWithNoWorktreeField() throws {
        // A thread persisted before these fields existed must decode with worktree == nil and stay
        // otherwise intact (the whole back-compat contract).
        let id = UUID()
        let legacy = """
        {"id":"\(id.uuidString)","title":"Legacy","mode":"auto","model":"tr/socrates",
         "messages":[],"events":[],"isPinned":false,"isArchived":false,
         "createdAt":0,"updatedAt":0}
        """
        let thread = try JSONDecoder().decode(ChatThread.self, from: Data(legacy.utf8))
        XCTAssertNil(thread.worktree)
        XCTAssertNil(thread.forkParentThreadID)
        XCTAssertEqual(thread.title, "Legacy")
        XCTAssertEqual(thread.id, id)
    }

    func testIsResolvableRequiresExistingPath() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertTrue(WorktreeBinding(path: dir.path, branch: "b").isResolvable)
        XCTAssertFalse(WorktreeBinding(path: dir.path + "-missing", branch: "b").isResolvable)
        XCTAssertFalse(WorktreeBinding(path: "", branch: "b").isResolvable)
    }

    func testSnapshotReferenceRoundTripsAndEnablesOnlyMissingDetachedRestore() throws {
        let reference = WorktreeSnapshotReference(
            headCommit: String(repeating: "a", count: 40),
            fileCount: 3,
            byteCount: 512
        )
        let missingPath = "/tmp/quillcode-missing-\(UUID().uuidString)"
        let binding = WorktreeBinding(
            path: missingPath,
            branch: "",
            base: "main",
            snapshot: reference
        )

        let decoded = try JSONDecoder().decode(
            WorktreeBinding.self,
            from: JSONEncoder().encode(binding)
        )

        XCTAssertEqual(decoded, binding)
        XCTAssertTrue(decoded.isDisposableManagedWorktree)
        XCTAssertTrue(decoded.canRestoreSnapshot)
        XCTAssertFalse(WorktreeBinding(
            path: missingPath,
            branch: "feature/permanent",
            snapshot: reference
        ).canRestoreSnapshot)
        XCTAssertFalse(WorktreeBinding(
            path: missingPath,
            branch: "",
            location: .local,
            snapshot: reference
        ).canRestoreSnapshot)
    }
}
