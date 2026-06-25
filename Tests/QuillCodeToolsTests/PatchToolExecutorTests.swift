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
}
