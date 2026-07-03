import XCTest
import Foundation
import QuillCodeCore
@testable import QuillCodeTools

// MARK: - Unit: the pure suggestion engine

final class FilePathSuggesterTests: XCTestCase {
    func testSuggestsCloseTypo() {
        let matches = FilePathSuggester.suggest(
            missing: "App.swfit",
            candidates: ["App.swift", "AppDelegate.swift", "README.md"]
        )
        XCTAssertEqual(matches.first, "App.swift")
    }

    func testTransposedAndDroppedCharacters() {
        XCTAssertEqual(
            FilePathSuggester.suggest(missing: "Pacakge.swift", candidates: ["Package.swift"]),
            ["Package.swift"]
        )
        XCTAssertEqual(
            FilePathSuggester.suggest(missing: "Makefil", candidates: ["Makefile", "Dockerfile"]),
            ["Makefile"]
        )
    }

    func testCaseOnlyDifferenceIsSuggested() {
        XCTAssertEqual(FilePathSuggester.suggest(missing: "readme.md", candidates: ["README.md"]), ["README.md"])
    }

    func testNormalizationOnlyDifferenceIsSuggested() {
        // NFC request vs NFD sibling: Swift `==` calls them equal, but on a byte-sensitive filesystem
        // (Linux ext4 = CI) they are different names and the NFD sibling IS the intended file. Assert
        // on bytes — an XCTAssertEqual on the strings would pass for either normalization form.
        let nfc = "caf\u{E9}.md"          // é precomposed
        let nfd = "cafe\u{301}.md"        // e + combining acute accent
        let matches = FilePathSuggester.suggest(missing: nfc, candidates: [nfd])
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].utf8.elementsEqual(nfd.utf8), "should suggest the on-disk (NFD) byte form")
    }

    func testByteIdenticalCandidateIsExcluded() {
        // The exact same bytes means the file exists; suggesting it back would be noise.
        XCTAssertTrue(FilePathSuggester.suggest(missing: "App.swift", candidates: ["App.swift"]).isEmpty)
    }

    func testNoSuggestionWhenNothingIsClose() {
        XCTAssertTrue(FilePathSuggester.suggest(missing: "App.swift", candidates: ["zebra.txt", "Makefile"]).isEmpty)
    }

    func testTightBudgetForShortNames() {
        // 2 edits on a 4-char name is a different name, not a typo.
        XCTAssertTrue(FilePathSuggester.suggest(missing: "a.md", candidates: ["c.rb"]).isEmpty)
    }

    func testSameExtensionWinsTies() {
        // "b.swift" and "a.md" are both distance 1 from... construct a tie: missing "ab.swift":
        // candidates "aa.swift" (dist 1, same ext) vs "ab.swifh" (dist 1, different ext).
        let matches = FilePathSuggester.suggest(missing: "ab.swift", candidates: ["ab.swifh", "aa.swift"])
        XCTAssertEqual(matches.first, "aa.swift")
    }

    func testLimitIsRespected() {
        let candidates = ["file1.txt", "file2.txt", "file3.txt", "file4.txt"]
        XCTAssertEqual(FilePathSuggester.suggest(missing: "file0.txt", candidates: candidates, limit: 2).count, 2)
    }

    func testFilesystemSuggestionsSkipOversizedParentDirectories() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        for index in 0...FilePathSuggester.maxCandidates {
            _ = FileManager.default.createFile(
                atPath: parent.appendingPathComponent("file-\(index).txt").path,
                contents: Data()
            )
        }

        let missing = parent.appendingPathComponent("mian.swift")
        XCTAssertTrue(FilePathSuggester.suggest(missingFileAt: missing).isEmpty)
    }

    func testNonPositiveLimitReturnsNoSuggestions() {
        let candidates = ["main.rs"]
        XCTAssertTrue(FilePathSuggester.suggest(missing: "mian.rs", candidates: candidates, limit: 0).isEmpty)
        XCTAssertTrue(FilePathSuggester.suggest(missing: "mian.rs", candidates: candidates, limit: -1).isEmpty)
    }

    func testEditDistanceCapEarlyExit() {
        XCTAssertEqual(FilePathSuggester.editDistance("abc", "abc", cap: 2), 0)
        XCTAssertEqual(FilePathSuggester.editDistance("abc", "abd", cap: 2), 1)
        XCTAssertGreaterThan(FilePathSuggester.editDistance("abcdefgh", "zyxwvuts", cap: 2), 2)
        XCTAssertEqual(FilePathSuggester.editDistance("abc", "abc", cap: -1), 0)
    }

    func testAdjacentTranspositionCountsAsOneEdit() {
        // The most common typo of all; plain Levenshtein's 2 would blow the short-name budget.
        XCTAssertEqual(FilePathSuggester.editDistance("mian.rs", "main.rs", cap: 3), 1)
        XCTAssertEqual(FilePathSuggester.suggest(missing: "mian.rs", candidates: ["main.rs", "lib.rs"]), ["main.rs"])
    }
}

// MARK: - Unit: the patch hunk-failure summarizer

final class PatchHunkFailureSummaryTests: XCTestCase {
    func testLiftsGitErrorLines() {
        let stderr = """
        checking patch Sources/App.swift...
        error: patch failed: Sources/App.swift:10
        error: Sources/App.swift: patch does not apply
        """
        let summary = PatchToolExecutor.hunkFailureSummary(fromStderr: stderr)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("patch failed: Sources/App.swift:10"), summary!)
        XCTAssertTrue(summary!.contains("Re-read the affected region"), summary!)
    }

    func testNoErrorLinesReturnsNil() {
        XCTAssertNil(PatchToolExecutor.hunkFailureSummary(fromStderr: "warning: something benign\n"))
        XCTAssertNil(PatchToolExecutor.hunkFailureSummary(fromStderr: ""))
    }

    func testManyErrorsAreBoundedWithOverflowCount() {
        let stderr = (1...8).map { "error: patch failed: F\($0).swift:1" }.joined(separator: "\n")
        let summary = PatchToolExecutor.hunkFailureSummary(fromStderr: stderr)!
        XCTAssertTrue(summary.contains("(+3 more)"), summary)
    }
}

// MARK: - Functional: through the real executors

final class RicherToolErrorsFunctionalTests: XCTestCase {
    private func makeWorkspace() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qc-err-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testReadOfTypoPathSuggestsSibling() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)

        let result = files.read(path: "Sources/App.swfit")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error!.contains("File not found: Sources/App.swfit"), result.error!)
        XCTAssertTrue(result.error!.contains("Did you mean: Sources/App.swift?"), result.error!)
    }

    func testSuggestionMessageCollapsesOddFilenamesToSingleLine() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "bad\nname.swift", content: "struct Bad {}\n").ok)

        let result = files.read(path: "bad\nnme.swift")

        XCTAssertFalse(result.ok)
        XCTAssertFalse(result.error!.contains("\n"), result.error!)
        XCTAssertTrue(result.error!.contains("bad nme.swift"), result.error!)
        XCTAssertTrue(result.error!.contains("bad name.swift"), result.error!)
    }

    func testReadOfMissingFileWithNoCloseSiblingIsPlain() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        let result = files.read(path: "nothing/like/it.txt")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error!.contains("File not found"), result.error!)
        XCTAssertFalse(result.error!.contains("Did you mean"), result.error!)
    }

    func testMissingWorkspaceRootDoesNotLeakParentSiblings() throws {
        // When the workspace root itself is missing (deleted or misconfigured), the missing path's
        // parent is OUTSIDE the workspace — sibling directory names there must not leak into the
        // model-facing error.
        let parent = try makeWorkspace()
        let root = parent.appendingPathComponent("app-v2")
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent("app-v1"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: parent.appendingPathComponent("app-v3"),
            withIntermediateDirectories: true
        )

        let files = FileToolExecutor(workspaceRoot: root)
        let result = files.read(path: ".")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error!.contains("File not found"), result.error!)
        XCTAssertFalse(result.error!.contains("Did you mean"), result.error!)
        XCTAssertFalse(result.error!.contains("app-v1"), result.error!)
        XCTAssertFalse(result.error!.contains("app-v3"), result.error!)
    }

    func testReadOfDirectoryPointsAtList() throws {
        let root = try makeWorkspace()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "x\n").ok)
        let result = files.read(path: "Sources")
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error!.contains("is a directory"), result.error!)
        XCTAssertTrue(result.error!.contains("host.file.list"), result.error!)
    }

    func testFailingPatchReportsWhichHunk() throws {
        let root = try makeWorkspace()
        // apply_patch runs `git apply`, which needs a repo.
        let shell = ShellToolExecutor()
        _ = shell.run(.init(command: "git init -q", cwd: root))
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "hello.txt", content: "actual content\n").ok)

        let patch = """
        diff --git a/hello.txt b/hello.txt
        --- a/hello.txt
        +++ b/hello.txt
        @@ -1 +1 @@
        -content that is not there
        +replacement
        """
        let result = PatchToolExecutor(workspaceRoot: root).apply(unifiedDiff: patch)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error!.contains("Patch does not apply"), result.error!)
        XCTAssertTrue(result.error!.contains("hello.txt"), result.error!)
    }
}

// MARK: - Integration: through the ToolRouter dispatch the agent uses

final class RicherToolErrorsRouterIntegrationTests: XCTestCase {
    func testRouterReadTypoCarriesSuggestion() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qc-err-router-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let router = ToolRouter(workspaceRoot: root)
        XCTAssertTrue(router.execute(
            ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: #"{"path":"main.rs","content":"fn main() {}\n"}"#
            )
        ).ok)

        let result = router.execute(
            ToolCall(name: ToolDefinition.fileRead.name, argumentsJSON: #"{"path":"mian.rs"}"#)
        )
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error!.contains("Did you mean: main.rs?"), result.error!)
    }
}
