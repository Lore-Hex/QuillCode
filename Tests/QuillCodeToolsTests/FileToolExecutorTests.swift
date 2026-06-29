import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class FileToolExecutorTests: XCTestCase {
    func testToolRouterExposesAndRoutesFileSearch() throws {
        let root = try makeTempDirectory()
        let files = FileToolExecutor(workspaceRoot: root)
        XCTAssertTrue(files.write(path: "Sources/App.swift", content: "struct RouterNeedle {}\n").ok)

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
        XCTAssertEqual(files.read(path: "nested/hello.txt").stdout, "hello world\n")
        XCTAssertFalse(files.write(path: "../escape.txt", content: "no").ok)
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
