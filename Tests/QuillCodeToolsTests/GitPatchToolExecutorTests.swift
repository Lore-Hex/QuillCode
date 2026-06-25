import XCTest
@testable import QuillCodeTools

final class GitPatchToolExecutorTests: XCTestCase {
    func testStageHunkStagesSelectedPatch() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "one\ntwo\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "one\nTWO\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """

        let result = GitToolExecutor().stageHunk(cwd: root, path: "hello.txt", patch: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(GitToolExecutor().diff(cwd: root, staged: true).stdout.contains("+TWO"))
        XCTAssertEqual(GitToolExecutor().diff(cwd: root).stdout, "")
    }

    func testStageHunkSupportsWorkspaceFileWithSpaces() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello world.txt")
        try "one\ntwo\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello world.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "one\nTWO\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello world.txt b/hello world.txt
        --- a/hello world.txt
        +++ b/hello world.txt
        @@ -1,2 +1,2 @@
         one
        -two
        +TWO
        """

        let result = GitToolExecutor().stageHunk(cwd: root, path: "hello world.txt", patch: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertTrue(GitToolExecutor().diff(cwd: root, staged: true).stdout.contains("+TWO"))
    }

    func testRestoreHunkRestoresSelectedPatch() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("hello.txt")
        try "one\ntwo\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(GitToolExecutor().stage(cwd: root, path: "hello.txt").ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m initial", cwd: root)).ok)
        try "one\nTWO\nthree\n".write(to: file, atomically: true, encoding: .utf8)
        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        """

        let result = GitToolExecutor().restoreHunk(cwd: root, path: "hello.txt", patch: patch)

        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "one\ntwo\nthree\n")
        XCTAssertEqual(GitToolExecutor().status(cwd: root).stdout, "## \(currentBranchName(in: root))\n")
    }

    func testHunkActionsRejectPatchPathMismatch() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let patch = """
        diff --git a/other.txt b/other.txt
        --- a/other.txt
        +++ b/other.txt
        @@ -1 +1 @@
        -old
        +new
        """

        let result = GitToolExecutor().stageHunk(cwd: root, path: "hello.txt", patch: patch)

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("different path") == true, result.error ?? "")
    }

    func testDetectsQuotedPatchPathMismatch() {
        let patch = """
        diff --git "a/hello world.txt" "b/other file.txt"
        --- "a/hello world.txt"
        +++ "b/other file.txt"
        @@ -1 +1 @@
        -old
        +new
        """

        let mismatch = GitPatchToolExecutor.mismatchedPatchPath(in: patch, expectedPath: "hello world.txt")

        XCTAssertEqual(mismatch, "other file.txt")
    }
}
