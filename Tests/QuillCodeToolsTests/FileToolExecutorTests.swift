import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class FileToolExecutorTests: XCTestCase {
    func testToolRouterExposesAndRoutesFileSearch() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct RouterNeedle {}\n").ok)

        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(ToolDefinition.fileList.name))
        XCTAssertTrue(ToolRouter.definitions.map(\.name).contains(ToolDefinition.fileSearch.name))
        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.fileSearch.name,
            argumentsJSON: ToolArguments.json(["query": "RouterNeedle"])
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileSearchToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.matches.map(\.path), ["Sources/App.swift"])
    }

    func testFileWriteStaysInsideWorkspace() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)

        let result = files.write(path: "nested/hello.txt", content: "hello world\n")

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(files.read(path: "nested/hello.txt").stdout, "1\thello world")
        XCTAssertFalse(files.write(path: "../escape.txt", content: "no").ok)
    }

    func testToolRouterAllowsEmptyFileWriteContent() throws {
        let root = try makeTempDirectory()
        try "old content\n".write(
            to: root.appendingPathComponent("rules.md"),
            atomically: true,
            encoding: .utf8
        )

        let result = ToolRouter(workspaceRoot: root).execute(ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "content": "",
                "path": "rules.md"
            ])
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("rules.md"), encoding: .utf8), "")
    }

    func testFileToolsRejectSymlinkEscapeOutsideWorkspace() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()  // a sibling dir, outside the workspace
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        // The agent could create such a symlink with `ln -s` via the shell, then try to read/write
        // through it — standardizedFileURL would not catch it, but the symlink-resolved check must.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape"),
            withDestinationURL: outside
        )
        let files = FileToolExecutor(workspaceRoot: root)

        XCTAssertFalse(files.write(path: "escape/evil.txt", content: "pwned").ok, "write through a symlink escaping the workspace must be rejected")
        XCTAssertFalse(files.read(path: "escape/secret.txt").ok, "read through a symlink escaping the workspace must be rejected")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outside.appendingPathComponent("evil.txt").path),
            "the rejected write must not have created a file outside the workspace"
        )
    }

    func testFileToolsAllowSymlinkPointingInsideWorkspace() throws {
        let root = try makeTempDirectory()
        let realDir = root.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        // A symlink that stays inside the workspace is legitimate and must keep working.
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link"),
            withDestinationURL: realDir
        )
        let files = FileToolExecutor(workspaceRoot: root)

        XCTAssertTrue(files.write(path: "link/ok.txt", content: "fine\n").ok)
        XCTAssertEqual(files.read(path: "real/ok.txt").stdout, "1\tfine")
    }

    func testFileToolsRejectMidPathAndNestedSymlinkEscapes() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let fm = FileManager.default

        // Mid-path symlink: the symlink is not the first component (`link/sub/...`).
        try fm.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        // Nested chain: a -> b -> outside.
        try fm.createSymbolicLink(at: root.appendingPathComponent("b"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: root.appendingPathComponent("a"), withDestinationURL: root.appendingPathComponent("b"))

        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertFalse(files.write(path: "link/sub/evil.txt", content: "x").ok, "mid-path symlink escape must be rejected")
        XCTAssertFalse(files.write(path: "a/evil.txt", content: "x").ok, "nested symlink-chain escape must be rejected")
        // The escapes wrote nothing outside.
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("sub/evil.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: outside.appendingPathComponent("evil.txt").path))
    }

    func testFileListAndSearchRejectSymlinkEscape() throws {
        let root = try makeTempDirectory()
        let outside = try makeTempDirectory()
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let files = FileToolExecutor(workspaceRoot: root)

        // list and search go through the same resolve() gate, so the escape is rejected there too.
        XCTAssertFalse(files.list(path: "escape").ok, "listing a symlink dir escaping the workspace must be rejected")
        XCTAssertFalse(files.search(query: "secret", path: "escape").ok, "searching through a symlink escape must be rejected")
    }

    func testFileListReturnsBoundedWorkspaceRelativeEntries() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct App {}\n").ok)
        XCTAssertTrue(files.write(path: "README.md", content: "# Smoke\n").ok)
        XCTAssertTrue(files.write(path: ".hidden", content: "secret-ish\n").ok)

        let result = files.list(maxEntries: 2)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileListToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.path, ".")
        XCTAssertFalse(output.includedHidden)
        XCTAssertEqual(output.totalEntries, 2)
        XCTAssertEqual(output.entries.map(\.path), ["Sources", "README.md"])
        XCTAssertEqual(output.entries.map(\.kind), ["directory", "file"])
        XCTAssertTrue(output.entries.first?.bytes == nil)
        XCTAssertEqual(output.entries.last?.bytes, 8)
        XCTAssertFalse(output.truncated)
        XCTAssertEqual(result.artifacts.count, 2)
    }

    func testFileListCanIncludeHiddenAndCapEntries() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: ".env.example", content: "API_KEY=\n").ok)
        XCTAssertTrue(files.write(path: "visible.txt", content: "hello\n").ok)

        let result = files.list(includeHidden: true, maxEntries: 1)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileListToolOutput.self, from: result.stdout)
        XCTAssertTrue(output.includedHidden)
        XCTAssertEqual(output.totalEntries, 2)
        XCTAssertEqual(output.entries.count, 1)
        XCTAssertTrue(output.truncated)
    }

    func testFileListRejectsFilesOutsideWorkspaceAndMissingDirectories() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "README.md", content: "# Smoke\n").ok)

        XCTAssertFalse(files.list(path: "README.md").ok)
        XCTAssertFalse(files.list(path: "../outside").ok)
        XCTAssertFalse(files.list(path: "Missing").ok)
    }

    func testFileSearchReturnsBoundedWorkspaceRelativeMatches() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "let target = \"needle\"\nlet other = 1\n").ok)
        XCTAssertTrue(files.write(path: "Tests/AppTests.swift", content: "XCTAssertEqual(target, \"needle\")\n").ok)
        XCTAssertTrue(files.write(path: "node_modules/ignored.js", content: "needle\n").ok)

        let result = files.search(query: "needle", maxResults: 10)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileSearchToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.query, "needle")
        XCTAssertEqual(output.path, ".")
        XCTAssertEqual(output.scannedFiles, 2)
        XCTAssertEqual(Set(output.matches.map(\.path)), ["Sources/App.swift", "Tests/AppTests.swift"])
        XCTAssertEqual(Set(output.matches.map(\.line)), [1])
        XCTAssertEqual(result.artifacts.count, 2)
    }

    func testFileSearchCanScopeToDirectoryAndCapResults() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/One.swift", content: "needle\nneedle again\n").ok)
        XCTAssertTrue(files.write(path: "Tests/Two.swift", content: "needle\n").ok)

        let result = files.search(query: "needle", path: "Sources", maxResults: 1)

        XCTAssertTrue(result.ok, result.error ?? "")
        let output = try JSONHelpers.decode(FileSearchToolOutput.self, from: result.stdout)
        XCTAssertEqual(output.path, "Sources")
        XCTAssertEqual(output.matches.count, 1)
        XCTAssertEqual(output.matches.first?.path, "Sources/One.swift")
        XCTAssertTrue(output.truncated)
    }

    func testFileSearchRejectsOutsideWorkspaceAndMissingQuery() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)

        XCTAssertFalse(files.search(query: "needle", path: "../outside").ok)
        XCTAssertFalse(files.search(query: "   ").ok)
    }
}
