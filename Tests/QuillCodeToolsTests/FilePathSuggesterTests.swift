import XCTest
@testable import QuillCodeTools

final class FilePathSuggesterTests: XCTestCase {
    func testRanksClosestSiblingFirstAndSkipsDissimilarNames() throws {
        let root = try makeTempDirectory()
        for name in ["FileToolExecutor.swift", "FileToolModels.swift", "README.md"] {
            try Data().write(to: root.appendingPathComponent(name))
        }

        let suggestions = FilePathSuggester.siblingSuggestions(
            forMissing: root.appendingPathComponent("FileToolExecuter.swift")
        )

        XCTAssertEqual(suggestions.first, "FileToolExecutor.swift")
        XCTAssertFalse(suggestions.contains("README.md"))
    }

    func testSuggestsSameStemWithDifferentExtension() throws {
        let root = try makeTempDirectory()
        try Data().write(to: root.appendingPathComponent("main.ts"))

        XCTAssertEqual(
            FilePathSuggester.siblingSuggestions(forMissing: root.appendingPathComponent("main.js")),
            ["main.ts"]
        )
    }

    func testSuggestsStemPrefixMatch() throws {
        let root = try makeTempDirectory()
        try Data().write(to: root.appendingPathComponent("FileToolExecutor.swift"))

        XCTAssertEqual(
            FilePathSuggester.siblingSuggestions(forMissing: root.appendingPathComponent("FileTool.swift")),
            ["FileToolExecutor.swift"]
        )
    }

    func testAbsentDirectoryYieldsNoSuggestions() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/file.txt")

        XCTAssertEqual(FilePathSuggester.siblingSuggestions(forMissing: missing), [])
    }

    func testLimitsSuggestionsToThree() throws {
        let root = try makeTempDirectory()
        for index in 1...6 {
            try Data().write(to: root.appendingPathComponent("note\(index).txt"))
        }

        let suggestions = FilePathSuggester.siblingSuggestions(forMissing: root.appendingPathComponent("note.txt"))

        XCTAssertEqual(suggestions.count, 3)
    }

    func testDissimilarSiblingsYieldNoSuggestions() throws {
        let root = try makeTempDirectory()
        try Data().write(to: root.appendingPathComponent("zebra.png"))

        XCTAssertEqual(
            FilePathSuggester.siblingSuggestions(forMissing: root.appendingPathComponent("config.yml")),
            []
        )
    }

    func testHiddenSiblingsAreOnlySuggestedForHiddenTargets() throws {
        let root = try makeTempDirectory()
        try Data().write(to: root.appendingPathComponent(".gitignore"))

        XCTAssertEqual(
            FilePathSuggester.siblingSuggestions(forMissing: root.appendingPathComponent("gitignore")),
            []
        )
        XCTAssertEqual(
            FilePathSuggester.siblingSuggestions(forMissing: root.appendingPathComponent(".gitignor")),
            [".gitignore"]
        )
    }

    func testMissingFileMessageKeepsRequestedDirectoryPrefix() throws {
        let root = try makeTempDirectory()
        let sources = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data().write(to: sources.appendingPathComponent("File.swift"))

        let message = FilePathSuggester.missingFileMessage(
            requestedPath: "Sources/Fil.swift",
            resolvedURL: sources.appendingPathComponent("Fil.swift")
        )

        XCTAssertTrue(message.contains("Path does not exist in the workspace: Sources/Fil.swift"), message)
        XCTAssertTrue(message.contains("Did you mean: Sources/File.swift?"), message)
    }

    func testFileReadOfMissingFileSuggestsSiblings() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/File.swift", content: "struct A {}\n").ok)

        let result = files.read(path: "Sources/Fil.swift")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Did you mean: Sources/File.swift?") == true, result.error ?? "")
    }

    func testFileReadOfMissingFileWithoutCandidatesOmitsDidYouMean() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/File.swift", content: "struct A {}\n").ok)

        let result = files.read(path: "Sources/Unrelated.xyz")

        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("Path does not exist in the workspace") == true, result.error ?? "")
        XCTAssertFalse(result.error?.contains("Did you mean") == true, result.error ?? "")
    }
}
