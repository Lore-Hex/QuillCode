import XCTest
@testable import QuillCodeTools

final class GitPatchToolExecutorTurnTests: XCTestCase {
    private func commitAll(_ root: URL, message: String) {
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git add -A", cwd: root)).ok)
        XCTAssertTrue(ShellToolExecutor().run(.init(command: "git commit -m \(message)", cwd: root)).ok)
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testReverseAppliesAMultiFileTurnPatch() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let a = root.appendingPathComponent("a.txt")
        let b = root.appendingPathComponent("b.txt")
        try write("a-old\n", to: a)
        try write("b-old\n", to: b)
        commitAll(root, message: "initial")

        // The "turn" edits both files; capture exactly what it changed.
        try write("a-new\n", to: a)
        try write("b-new\n", to: b)
        let patch = GitToolExecutor().diff(cwd: root).stdout
        XCTAssertFalse(patch.isEmpty)

        let result = GitPatchToolExecutor().restoreTurnPatch(cwd: root, patches: [patch])
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "a-old\n")
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "b-old\n")
    }

    func testFailsCleanlyWhenFilesChangedSinceAndDoesNotRestoreToHEAD() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let a = root.appendingPathComponent("a.txt")
        try write("old\n", to: a)
        commitAll(root, message: "initial")

        try write("new\n", to: a)
        let patch = GitToolExecutor().diff(cwd: root).stdout
        commitAll(root, message: "turn")

        // A LATER edit (the user's own) touches the same line.
        try write("newer\n", to: a)

        let result = GitPatchToolExecutor().restoreTurnPatch(cwd: root, patches: [patch])
        // The reverse cannot apply cleanly: fail rather than corrupt or restore-to-HEAD.
        XCTAssertFalse(result.ok)
        // CRITICAL: the user's later edit is untouched — no silent `git restore` to HEAD ("new").
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "newer\n")
    }

    func testDeletesAFileTheTurnCreated() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        try write("base\n", to: root.appendingPathComponent("base.txt"))
        commitAll(root, message: "initial")

        // The turn created new.txt — an apply_patch add-hunk (/dev/null -> b/new.txt).
        let created = root.appendingPathComponent("new.txt")
        try write("created\n", to: created)
        let addPatch = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,1 @@
        +created
        """

        let result = GitPatchToolExecutor().restoreTurnPatch(cwd: root, patches: [addPatch])
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
    }

    func testAppliesPatchesNewestFirstSoCreateThenEditUnwinds() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let a = root.appendingPathComponent("a.txt")
        try write("old\n", to: a)
        commitAll(root, message: "initial")

        try write("mid\n", to: a)
        let patch1 = GitToolExecutor().diff(cwd: root).stdout
        commitAll(root, message: "edit1")

        try write("new\n", to: a)
        let patch2 = GitToolExecutor().diff(cwd: root).stdout

        // Reverting the turn [patch1, patch2] must unwind patch2 then patch1 -> back to "old".
        let result = GitPatchToolExecutor().restoreTurnPatch(cwd: root, patches: [patch1, patch2])
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "old\n")
    }

    func testRollsBackACreatedFileInANewDirectoryWhenAnEarlierPatchFails() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let a = root.appendingPathComponent("a.txt")
        try write("old\n", to: a)
        commitAll(root, message: "initial")

        // The turn created sub/new.txt (still on disk) and edited a.txt old->mid.
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let created = sub.appendingPathComponent("new.txt")
        try write("created\n", to: created)
        let createPatch = """
        diff --git a/sub/new.txt b/sub/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/sub/new.txt
        @@ -0,0 +1,1 @@
        +created
        """
        // a.txt is "old", so reverting the a.txt edit (expects "mid") will FAIL — but only
        // AFTER the newest patch (the create) reverse-applies and prunes sub/.
        let editPatch = """
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -old
        +mid
        """

        let result = GitPatchToolExecutor().restoreTurnPatch(cwd: root, patches: [editPatch, createPatch])

        XCTAssertFalse(result.ok)
        // The whole revert rolled back: the created file is restored (its pruned dir recreated).
        XCTAssertTrue(FileManager.default.fileExists(atPath: created.path))
        XCTAssertEqual(try String(contentsOf: created, encoding: .utf8), "created\n")
        XCTAssertEqual(try String(contentsOf: a, encoding: .utf8), "old\n")
    }

    func testReverseRecreatesAFileTheTurnDeleted() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        let file = root.appendingPathComponent("gone.txt")
        try write("content\n", to: file)
        commitAll(root, message: "initial")

        // The turn deleted gone.txt (apply_patch delete-hunk).
        try FileManager.default.removeItem(at: file)
        let deletePatch = """
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        --- a/gone.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -content
        """

        let result = GitPatchToolExecutor().restoreTurnPatch(cwd: root, patches: [deletePatch])
        XCTAssertTrue(result.ok, "\(result.error ?? "") \(result.stderr)")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "content\n")
    }

    func testEmptyPatchesFail() throws {
        let root = try makeTempDirectory()
        try initializeGitRepo(at: root)
        XCTAssertFalse(GitPatchToolExecutor().restoreTurnPatch(cwd: root, patches: ["   "]).ok)
    }
}
