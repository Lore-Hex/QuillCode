import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentImmediateFileActionTests: XCTestCase {
    func testListFilesQuestionExecutesImmediatelyWithoutProviderRoundTrip() async throws {
        let root = try makeTempDirectory()
        try "alpha\n".write(to: root.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try "beta\n".write(to: root.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Can you list the files here?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        let list = try queuedFileList(in: result)
        XCTAssertEqual(list.path, ".")
        XCTAssertFalse(list.includeHidden)
        XCTAssertTrue(result.thread.messages.last?.content.contains("alpha.txt") == true)
        XCTAssertTrue(result.thread.messages.last?.content.contains("beta.txt") == true)
        XCTAssertNoAssistantMessageContains("I'll list", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testListFilesCanScopeToDirectoryAndIncludeHidden() async throws {
        let root = try makeTempDirectory()
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )
        try "visible\n".write(to: root.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "hidden\n".write(to: root.appendingPathComponent("Sources/.secret"), atomically: true, encoding: .utf8)
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Can you list all files in Sources?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        let list = try queuedFileList(in: result)
        XCTAssertEqual(list.path, "Sources")
        XCTAssertTrue(list.includeHidden)
        XCTAssertTrue(result.thread.messages.last?.content.contains("Sources/.secret") == true)
        XCTAssertTrue(result.thread.messages.last?.content.contains("Sources/App.swift") == true)
    }

    func testMakeHelloWorldFileExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send(
            "Can you write a file that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        let text = try String(contentsOf: root.appendingPathComponent("hello.txt"), encoding: .utf8)
        XCTAssertEqual(text, "hello world\n")
        XCTAssertEqual(result.thread.messages.last?.content, "Wrote `hello.txt`.")
    }

    func testFollowUpReadIgnoresPreviousToolFeedback() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner()
        let writeResult = try await runner.send(
            "Can you write a file that says hello world",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let readResult = try await runner.send(
            "Read `hello.txt` and tell me its exact content",
            in: writeResult.thread,
            workspaceRoot: root
        )

        XCTAssertEqual(try queuedFileRead(in: readResult), "hello.txt")
        XCTAssertEqual(readResult.thread.messages.last?.content, "Contents of `hello.txt`:\n1\thello world")
        XCTAssertEqual(
            readResult.thread.messages.filter { $0.role == .assistant }.map(\.content),
            ["Wrote `hello.txt`.", "Contents of `hello.txt`:\n1\thello world"]
        )
    }

    func testNamedFileWriteExecutesImmediatelyWithoutProviderRoundTrip() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Create a file named notes/todo.txt that says \"buy milk\"",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("notes/todo.txt"), encoding: .utf8),
            "buy milk\n"
        )
        let write = try queuedFileWrite(in: result)
        XCTAssertEqual(write.path, "notes/todo.txt")
        XCTAssertEqual(write.content, "buy milk\n")
    }

    func testBacktickFileReadExecutesImmediatelyWithoutProviderRoundTrip() async throws {
        let root = try makeTempDirectory()
        try "hello world\n".write(to: root.appendingPathComponent("hello.txt"), atomically: true, encoding: .utf8)
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Read `hello.txt` and tell me its exact content",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedFileRead(in: result), "hello.txt")
        XCTAssertEqual(result.thread.messages.last?.content, "Contents of `hello.txt`:\n1\thello world")
        XCTAssertNoAssistantMessageContains("I'll read", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testNaturalFileReadExecutesImmediatelyWithStructuredFileTool() async throws {
        let root = try makeTempDirectory()
        try "# QuillCode\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "What is in README.md?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedFileRead(in: result), "README.md")
        XCTAssertEqual(result.thread.messages.last?.content, "Contents of `README.md`:\n1\t# QuillCode")
        XCTAssertNoAssistantMessageContains("I'll read", in: result)
        XCTAssertNoAssistantMessageContains("I will read", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testNaturalFileSearchExecutesImmediatelyWithStructuredFileTool() async throws {
        let root = try makeTempDirectory()
        let sources = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "struct AgentRunner {}\n".write(
            to: sources.appendingPathComponent("Agent.swift"),
            atomically: true,
            encoding: .utf8
        )
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Find AgentRunner",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        let search = try queuedFileSearch(in: result)
        XCTAssertEqual(search.query, "AgentRunner")
        XCTAssertNil(search.path)
        XCTAssertTrue(result.thread.messages.last?.content.contains("Found 1 match for `AgentRunner`:") == true)
        XCTAssertTrue(result.thread.messages.last?.content.contains("`Sources/Agent.swift:1`") == true)
        XCTAssertNoAssistantMessageContains("I'll search", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testFileWriteWithQuotedContentDefaultsToNotePath() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Make a file with content `ship the first build`",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("note.txt"), encoding: .utf8),
            "ship the first build\n"
        )
        let write = try queuedFileWrite(in: result)
        XCTAssertEqual(write.path, "note.txt")
        XCTAssertEqual(write.content, "ship the first build\n")
    }

    func testAmbiguousMakeFileRequestStillUsesModel() async throws {
        let root = try makeTempDirectory()
        let runner = fixedSayAgentRunner("What should the file contain?")

        let result = try await runner.send("Make a file", in: ChatThread(mode: .auto), workspaceRoot: root)

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "What should the file contain?")
    }
}
