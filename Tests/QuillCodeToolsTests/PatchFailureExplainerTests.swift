import XCTest
@testable import QuillCodeTools

final class PatchFailureExplainerTests: XCTestCase {
    private let threeHunkPatch = """
    diff --git a/big.txt b/big.txt
    --- a/big.txt
    +++ b/big.txt
    @@ -1,3 +1,3 @@
     a1
    -a2
    +A2
     a3
    @@ -6,3 +6,3 @@
     a6
    -WRONG
    +A7
     a8
    @@ -10,3 +10,3 @@
     a10
    -a11
    +A11
     a12
    """

    func testNamesFailingHunkAndLine() throws {
        let root = try makeTempDirectory()

        let message = PatchFailureExplainer.explain(
            stderr: "error: patch failed: big.txt:6\nerror: big.txt: patch does not apply\n",
            patch: threeHunkPatch,
            workspaceRoot: root
        )

        XCTAssertTrue(message?.contains("Hunk 2 of 3 for 'big.txt'") == true, message ?? "nil")
        XCTAssertTrue(message?.contains("line 6") == true, message ?? "nil")
        // The generic "does not apply" line for the same file is folded into the hunk report.
        XCTAssertFalse(message?.contains("does not apply to the current file content") == true, message ?? "nil")
    }

    func testMissingPatchTargetSuggestsSiblings() throws {
        let root = try makeTempDirectory()
        try "one\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)

        let message = PatchFailureExplainer.explain(
            stderr: "error: helo.txt: No such file or directory\n",
            patch: "--- a/helo.txt\n+++ b/helo.txt\n@@ -1 +1 @@\n-one\n+ONE\n",
            workspaceRoot: root
        )

        XCTAssertTrue(message?.contains("Patch target does not exist in the workspace: helo.txt") == true, message ?? "nil")
        XCTAssertTrue(message?.contains("Did you mean: hello.txt?") == true, message ?? "nil")
    }

    func testMalformedPatchReportsPatchLine() throws {
        let root = try makeTempDirectory()

        let message = PatchFailureExplainer.explain(
            stderr: "error: corrupt patch at line 4\n",
            patch: "--- a/x.txt\n+++ b/x.txt\n@@ garbage @@\n",
            workspaceRoot: root
        )

        XCTAssertTrue(message?.contains("malformed at patch line 4") == true, message ?? "nil")
    }

    func testNewFileConflictIsReported() throws {
        let root = try makeTempDirectory()

        let message = PatchFailureExplainer.explain(
            stderr: "error: hello.txt: already exists in working directory\n",
            patch: "--- /dev/null\n+++ b/hello.txt\n@@ -0,0 +1 @@\n+one\n",
            workspaceRoot: root
        )

        XCTAssertTrue(message?.contains("Patch creates a new file 'hello.txt'") == true, message ?? "nil")
    }

    func testUnrecognizedStderrReturnsNil() throws {
        let root = try makeTempDirectory()

        XCTAssertNil(PatchFailureExplainer.explain(
            stderr: "fatal: something unrelated\n",
            patch: threeHunkPatch,
            workspaceRoot: root
        ))
    }

    func testApplyPatchReportsFailingHunkThroughExecutor() throws {
        let root = try makeTempDirectory()
        let lines = (1...12).map { "a\($0)" }.joined(separator: "\n") + "\n"
        try lines.write(to: root.appendingPathComponent("big.txt"), atomically: true, encoding: .utf8)

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: threeHunkPatch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Hunk 2 of 3 for 'big.txt'") == true, result.error ?? "")
    }

    func testApplyPatchMissingFileSuggestsSiblingsThroughExecutor() throws {
        let root = try makeTempDirectory()
        try "one\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/helo.txt b/helo.txt
        --- a/helo.txt
        +++ b/helo.txt
        @@ -1 +1 @@
        -one
        +ONE
        """

        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Did you mean: hello.txt?") == true, result.error ?? "")
    }
}
