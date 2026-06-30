import XCTest
@testable import QuillCodeTools

final class PatchToolExecutorTests: XCTestCase {
    func testApplyPatchChangesWorkspaceFile() throws {
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("hello.txt")
        try "hello\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -hello
        +hello world
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello world\n")
    }

    func testApplyPatchRejectsUnsafePaths() throws {
        let root = try makeTempDirectory()
        let patch = """
        diff --git a/../escape.txt b/../escape.txt
        --- a/../escape.txt
        +++ b/../escape.txt
        @@ -1 +1 @@
        -old
        +new
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("unsafe path") == true, result.error ?? "")
    }

    func testApplyPatchRejectsSymlinkEscapePaths() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        // Lexically `escape/evil.txt` looks in-workspace (no ..), so only the symlink-resolved boundary
        // rejects it — and it must be rejected at the validator (error "unsafe path"), not left to
        // git apply's own symlink refusal.
        let patch = """
        diff --git a/escape/evil.txt b/escape/evil.txt
        --- /dev/null
        +++ b/escape/evil.txt
        @@ -0,0 +1 @@
        +pwned
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("unsafe path") == true, "expected validator rejection, got: \(result.error ?? "")")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("evil.txt").path))
    }
}
