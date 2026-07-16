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

    func testStrictApplyDisclosesNoTolerantMatch() throws {
        let root = try makeTempDirectory()
        try "hello\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -hello
        +hello world
        """
        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)
        XCTAssertTrue(result.ok)
        XCTAssertFalse(result.stdout.contains("tolerant match"), result.stdout)
    }

    func testMiscountedHunkHeaderAppliesViaRecountAndDiscloses() throws {
        // THE daily-drive failure shape: the model's hunk header line counts are wrong for the
        // hunk body it wrote. Strict git apply rejects it; --recount fixes the counts from the
        // body itself. The tolerant rung must apply AND disclose itself.
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("main.py")
        try "def add(a, b):\n    # BUG: subtracts\n    return a - b\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/main.py b/main.py
        --- a/main.py
        +++ b/main.py
        @@ -1,9 +1,7 @@
         def add(a, b):
        -    # BUG: subtracts
        -    return a - b
        +    return a + b
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("tolerant match"), result.stdout)
        XCTAssertEqual(
            try String(contentsOf: file, encoding: .utf8),
            "def add(a, b):\n    return a + b\n"
        )
    }

    func testWhitespaceDriftedContextAppliesViaTolerantRung() throws {
        // Context lines whose indentation drifted (tabs vs spaces) fail strict apply but land via
        // --ignore-whitespace.
        let root = try makeTempDirectory()
        let file = root.appendingPathComponent("config.txt")
        try "alpha\n\tindented line\nomega\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/config.txt b/config.txt
        --- a/config.txt
        +++ b/config.txt
        @@ -1,3 +1,3 @@
         alpha
             indented line
        -omega
        +OMEGA
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(result.stdout.contains("tolerant match"), result.stdout)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "alpha\n\tindented line\nOMEGA\n")
    }

    func testTrulyInapplicablePatchStillFailsWithStrictDiagnostics() throws {
        // Wrong content entirely: every rung fails, and the model sees the STRICT rung's precise
        // "patch failed: file:line" diagnostics, not a looser rung's vaguer message.
        let root = try makeTempDirectory()
        try "completely different\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -no such line anywhere
        +replacement
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Patch does not apply") == true, result.error ?? "")
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

    func testApplyPatchRejectsQuotedSymlinkEscapePaths() throws {
        let parent = try makeTempDirectory()
        let root = parent.appendingPathComponent("repo")
        let outside = parent.appendingPathComponent("outside dir")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape dir"),
            withDestinationURL: outside
        )
        let patch = """
        diff --git "a/escape dir/evil file.txt" "b/escape dir/evil file.txt"
        new file mode 100644
        --- /dev/null
        +++ "b/escape dir/evil file.txt"
        @@ -0,0 +1 @@
        +pwned
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("unsafe path") == true, result.error ?? "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("evil file.txt").path))
    }
}
