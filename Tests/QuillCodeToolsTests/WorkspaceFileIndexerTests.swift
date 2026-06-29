import XCTest
@testable import QuillCodeTools

final class WorkspaceFileIndexerTests: XCTestCase {
    func testIndexReturnsSortedWorkspaceRelativeFiles() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(files.write(path: "Sources/Helpers/Util.swift", content: "enum Util {}\n").ok)
        XCTAssertTrue(files.write(path: "README.md", content: "# Readme\n").ok)

        let index = WorkspaceFileIndexer(workspaceRoot: root).index()

        XCTAssertEqual(index.entries.map(\.path), [
            "README.md",
            "Sources/App.swift",
            "Sources/Helpers/Util.swift"
        ])
        XCTAssertFalse(index.truncated)
    }

    func testIndexCarriesNameAndDirectoryMetadata() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/Helpers/Util.swift", content: "enum Util {}\n").ok)
        XCTAssertTrue(files.write(path: "README.md", content: "# Readme\n").ok)

        let entries = WorkspaceFileIndexer(workspaceRoot: root).index().entries
        let util = try XCTUnwrap(entries.first { $0.path == "Sources/Helpers/Util.swift" })
        XCTAssertEqual(util.name, "Util.swift")
        XCTAssertEqual(util.directory, "Sources/Helpers")

        let readme = try XCTUnwrap(entries.first { $0.path == "README.md" })
        XCTAssertEqual(readme.name, "README.md")
        XCTAssertEqual(readme.directory, "")
    }

    func testIndexSkipsHeavyDependencyAndBuildDirectories() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(files.write(path: "node_modules/dep/index.js", content: "module.exports = {}\n").ok)
        XCTAssertTrue(files.write(path: ".build/debug/App.o", content: "binary\n").ok)
        XCTAssertTrue(files.write(path: ".git/config", content: "[core]\n").ok)

        let paths = WorkspaceFileIndexer(workspaceRoot: root).index().entries.map(\.path)

        XCTAssertEqual(paths, ["Sources/App.swift"])
    }

    func testIndexSkipsHiddenEntriesByDefaultAndIncludesThemOnRequest() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(files.write(path: ".env", content: "TOKEN=x\n").ok)
        XCTAssertTrue(files.write(path: ".config/settings.json", content: "{}\n").ok)

        let defaultPaths = WorkspaceFileIndexer(workspaceRoot: root).index().entries.map(\.path)
        XCTAssertEqual(defaultPaths, ["Sources/App.swift"])

        let hiddenPaths = WorkspaceFileIndexer(workspaceRoot: root).index(includeHidden: true).entries.map(\.path)
        XCTAssertEqual(hiddenPaths, [".config/settings.json", ".env", "Sources/App.swift"])
    }

    func testIndexHonorsFileCapAndReportsTruncation() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        for offset in 0..<5 {
            XCTAssertTrue(files.write(path: "file-\(offset).txt", content: "x\n").ok)
        }

        let index = WorkspaceFileIndexer(workspaceRoot: root).index(maxFiles: 3)

        XCTAssertEqual(index.entries.count, 3)
        XCTAssertTrue(index.truncated)
    }

    func testIndexOnMissingRootReturnsEmpty() {
        let missing = URL(fileURLWithPath: "/tmp/quillcode-missing-\(UUID().uuidString)")
        let index = WorkspaceFileIndexer(workspaceRoot: missing).index()
        XCTAssertTrue(index.isEmpty)
        XCTAssertFalse(index.truncated)
    }
}
