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

        XCTAssertEqual(index.entries.filter { $0.kind == .file }.map(\.path), [
            "README.md",
            "Sources/App.swift",
            "Sources/Helpers/Util.swift"
        ])
        XCTAssertFalse(index.truncated)
    }

    func testIndexEmitsDirectoryEntriesInterleavedWithFiles() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "README.md", content: "# Readme\n").ok)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(files.write(path: "Sources/Helpers/Util.swift", content: "enum Util {}\n").ok)

        let entries = WorkspaceFileIndexer(workspaceRoot: root).index().entries
        XCTAssertEqual(entries.map { "\($0.path):\($0.kind.rawValue)" }, [
            "README.md:file",
            "Sources:directory",
            "Sources/App.swift:file",
            "Sources/Helpers:directory",
            "Sources/Helpers/Util.swift:file"
        ])
        let helpers = try XCTUnwrap(entries.first { $0.path == "Sources/Helpers" })
        XCTAssertEqual(helpers.name, "Helpers")
        XCTAssertEqual(helpers.directory, "Sources")
    }

    func testDirectoriesDoNotConsumeTheFileBudget() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        // 5 files across 5 directories, comfortably under the file cap.
        for index in 0..<5 {
            XCTAssertTrue(files.write(path: "dir-\(index)/file.txt", content: "x\n").ok)
        }

        let index = WorkspaceFileIndexer(workspaceRoot: root).index(maxFiles: 50)
        // All 5 files survive — the 5 directory entries did not eat into the file budget — and
        // a complete scan flags neither set as truncated.
        XCTAssertEqual(index.entries.filter { $0.kind == .file }.count, 5)
        XCTAssertEqual(index.entries.filter { $0.kind == .directory }.count, 5)
        XCTAssertFalse(index.truncated)
        XCTAssertFalse(index.directoriesTruncated)
    }

    func testFileCapTruncationAlsoFlagsDirectoriesAsIncomplete() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        // Far more files than the cap, spread across many directories. The depth-first
        // enumerator aborts when the file cap is hit, so directories deeper in the walk are
        // never visited — the index must NOT report that partial directory set as complete.
        for index in 0..<20 {
            XCTAssertTrue(files.write(path: "dir-\(index)/file.txt", content: "x\n").ok)
        }

        let index = WorkspaceFileIndexer(workspaceRoot: root).index(maxFiles: 2)
        XCTAssertEqual(index.entries.filter { $0.kind == .file }.count, 2)
        XCTAssertTrue(index.truncated)
        // The honest signal: enumeration stopped early, so the directory set is incomplete.
        XCTAssertTrue(index.directoriesTruncated)
        XCTAssertLessThan(index.entries.filter { $0.kind == .directory }.count, 20)
    }

    func testWorkspaceFileIndexEntryDecodesLegacyJSONWithoutKind() throws {
        let json = #"{"path":"Sources/App.swift","name":"App.swift","directory":"Sources"}"#
        let entry = try JSONDecoder().decode(WorkspaceFileIndexEntry.self, from: Data(json.utf8))
        XCTAssertEqual(entry.kind, .file)
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

        let paths = WorkspaceFileIndexer(workspaceRoot: root).index().entries.filter { $0.kind == .file }.map(\.path)

        XCTAssertEqual(paths, ["Sources/App.swift"])
    }

    func testIndexSkipsHiddenEntriesByDefaultAndIncludesThemOnRequest() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(files.write(path: ".env", content: "TOKEN=x\n").ok)
        XCTAssertTrue(files.write(path: ".config/settings.json", content: "{}\n").ok)

        let defaultPaths = WorkspaceFileIndexer(workspaceRoot: root).index().entries.filter { $0.kind == .file }.map(\.path)
        XCTAssertEqual(defaultPaths, ["Sources/App.swift"])

        let hiddenPaths = WorkspaceFileIndexer(workspaceRoot: root).index(includeHidden: true).entries.filter { $0.kind == .file }.map(\.path)
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
