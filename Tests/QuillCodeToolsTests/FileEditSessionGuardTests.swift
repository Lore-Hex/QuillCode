import XCTest
import QuillCodeCore
@testable import QuillCodeTools

// MARK: - Read-before-write enforcement through FileToolExecutor

final class FileEditSessionGuardWriteTests: XCTestCase {
    func testWriteToExistingUnreadFileIsBlocked() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root, editGuard: FileEditSessionGuard())
        try "precious\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let result = files.write(path: "notes.txt", content: "clobbered\n")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("not read in this session") == true, result.error ?? "")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8),
            "precious\n",
            "a blocked write must leave the file untouched"
        )
    }

    func testWriteAllowedAfterRead() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root, editGuard: FileEditSessionGuard())
        try "old\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertTrue(files.read(path: "notes.txt").ok)
        let result = files.write(path: "notes.txt", content: "new\n")

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("notes.txt"), encoding: .utf8), "new\n")
    }

    func testNewFileCreationAllowedWithoutRead() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root, editGuard: FileEditSessionGuard())

        let result = files.write(path: "nested/fresh.txt", content: "hello\n")

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("nested/fresh.txt"), encoding: .utf8),
            "hello\n"
        )
    }

    func testWriteMarksFileAsReadForSubsequentWrites() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root, editGuard: FileEditSessionGuard())

        XCTAssertTrue(files.write(path: "draft.txt", content: "one\n").ok)
        // The session wrote the file, so it knows the content — no host.file.read required.
        let second = files.write(path: "draft.txt", content: "two\n")

        XCTAssertTrue(second.ok, second.error ?? "")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("draft.txt"), encoding: .utf8), "two\n")
    }

    func testNoOpWriteRejectedWithDistinctError() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root, editGuard: FileEditSessionGuard())
        try "same\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        XCTAssertTrue(files.read(path: "notes.txt").ok)

        let noOp = files.write(path: "notes.txt", content: "same\n")

        XCTAssertFalse(noOp.ok)
        XCTAssertTrue(noOp.error?.contains("No-op write") == true, noOp.error ?? "")
        XCTAssertFalse(
            noOp.error?.contains("not read in this session") == true,
            "the no-op rejection must be distinguishable from the unread-file rejection"
        )
        // A real edit still goes through afterwards.
        XCTAssertTrue(files.write(path: "notes.txt", content: "different\n").ok)
    }

    func testUnguardedExecutorKeepsLegacyBehavior() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        try "old\n".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        XCTAssertTrue(files.write(path: "notes.txt", content: "new\n").ok)
        XCTAssertTrue(files.write(path: "notes.txt", content: "new\n").ok, "no-op writes stay allowed without a guard")
    }
}

// MARK: - Read-before-patch enforcement through PatchToolExecutor

final class FileEditSessionGuardPatchTests: XCTestCase {
    private let helloPatch = """
    diff --git a/hello.txt b/hello.txt
    --- a/hello.txt
    +++ b/hello.txt
    @@ -1 +1 @@
    -hello
    +hello world
    """

    func testPatchToExistingUnreadFileIsBlocked() throws {
        let root = try makeTempDirectory()
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let patcher = PatchToolExecutor(workspaceRoot: root, editGuard: FileEditSessionGuard())

        let result = patcher.apply(unifiedDiff: helloPatch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Refusing to patch hello.txt") == true, result.error ?? "")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8),
            "hello\n",
            "a blocked patch must leave the file untouched"
        )
    }

    func testPatchAllowedAfterRead() throws {
        let root = try makeTempDirectory()
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let editGuard = FileEditSessionGuard()

        XCTAssertTrue(FileToolExecutor(workspaceRoot: root, editGuard: editGuard).read(path: "hello.txt").ok)
        let result = PatchToolExecutor(workspaceRoot: root, editGuard: editGuard).apply(unifiedDiff: helloPatch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8),
            "hello world\n"
        )
    }

    func testPatchCreatingNewFileAllowedAndMarksItRead() throws {
        let root = try makeTempDirectory()
        let editGuard = FileEditSessionGuard()
        let patch = """
        diff --git a/fresh.txt b/fresh.txt
        new file mode 100644
        --- /dev/null
        +++ b/fresh.txt
        @@ -0,0 +1 @@
        +fresh
        """

        let result = PatchToolExecutor(workspaceRoot: root, editGuard: editGuard).apply(unifiedDiff: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        // The session created the file via the patch, so a follow-up write needs no read.
        let write = FileToolExecutor(workspaceRoot: root, editGuard: editGuard)
            .write(path: "fresh.txt", content: "rewritten\n")
        XCTAssertTrue(write.ok, write.error ?? "")
    }

    func testTargetPathsParsesDiffMetadata() {
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -hello
        +hello world
        diff --git a/fresh.txt b/fresh.txt
        --- /dev/null
        +++ b/fresh.txt
        @@ -0,0 +1 @@
        +fresh
        """

        XCTAssertEqual(PatchToolExecutor.targetPaths(in: patch), ["hello.txt", "fresh.txt"])
    }
}

// MARK: - Enforcement through the ToolRouter dispatch the agent and app use

final class FileEditSessionGuardRouterTests: XCTestCase {
    func testRouterGuardsWriteAcrossSeparateRouterInstances() throws {
        // Both the agent and desktop paths construct a fresh ToolRouter per tool call, so the
        // read-set must survive across instances sharing one session guard.
        let root = try makeTempDirectory()
        let editGuard = FileEditSessionGuard()
        try "old\n".write(to: root.appendingPathComponent("rules.md"), atomically: true, encoding: .utf8)
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "rules.md", "content": "new\n"])
        )

        let blocked = ToolRouter(workspaceRoot: root, editGuard: editGuard).execute(write)
        XCTAssertFalse(blocked.ok)
        XCTAssertTrue(blocked.error?.contains("not read in this session") == true, blocked.error ?? "")

        let read = ToolRouter(workspaceRoot: root, editGuard: editGuard).execute(ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "rules.md"])
        ))
        XCTAssertTrue(read.ok, read.error ?? "")

        let allowed = ToolRouter(workspaceRoot: root, editGuard: editGuard).execute(write)
        XCTAssertTrue(allowed.ok, allowed.error ?? "")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("rules.md"), encoding: .utf8), "new\n")
    }
}

// MARK: - Per-file lock serialization

/// Lock-protected mutable state the strict-concurrency checker accepts inside
/// `DispatchQueue.concurrentPerform`.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

final class FileEditSessionGuardConcurrencyTests: XCTestCase {
    func testConcurrentExclusiveAccessToSameFileIsSerialized() throws {
        let root = try makeTempDirectory()
        let editGuard = FileEditSessionGuard()
        let url = root.appendingPathComponent("contended.txt")
        let occupancy = LockedBox((active: 0, maxActive: 0))

        DispatchQueue.concurrentPerform(iterations: 64) { index in
            editGuard.withExclusiveAccess(to: [url]) {
                occupancy.withValue {
                    $0.active += 1
                    $0.maxActive = max($0.maxActive, $0.active)
                }
                // Real work inside the critical section so an overlapping entry would be observed.
                try? "iteration \(index)\n".write(to: url, atomically: true, encoding: .utf8)
                occupancy.withValue { $0.active -= 1 }
            }
        }

        XCTAssertEqual(occupancy.withValue(\.maxActive), 1, "two edits held the same file's lock at once")
    }

    func testOpposingMultiFileLockOrdersDoNotDeadlock() throws {
        let root = try makeTempDirectory()
        let editGuard = FileEditSessionGuard()
        let first = root.appendingPathComponent("a.txt")
        let second = root.appendingPathComponent("b.txt")

        // Opposite argument orders would deadlock an implementation that locks in argument
        // order; sorted-key acquisition must let every iteration complete.
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let urls = index.isMultiple(of: 2) ? [first, second] : [second, first]
            editGuard.withExclusiveAccess(to: urls) {}
        }
    }

    func testConcurrentGuardedWritesEachLandAtomically() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root, editGuard: FileEditSessionGuard())
        XCTAssertTrue(files.write(path: "shared.txt", content: "start\n").ok)

        let collected = LockedBox([ToolResult]())
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            let result = files.write(path: "shared.txt", content: "content-\(index)\n")
            collected.withValue { $0.append(result) }
        }

        let results = collected.withValue { $0 }
        XCTAssertTrue(results.allSatisfy(\.ok), results.compactMap(\.error).joined(separator: "; "))
        let final = try String(contentsOf: root.appendingPathComponent("shared.txt"), encoding: .utf8)
        XCTAssertTrue(
            (0..<16).map { "content-\($0)\n" }.contains(final),
            "the surviving content must be exactly one write, not an interleaving: \(final)"
        )
    }
}
