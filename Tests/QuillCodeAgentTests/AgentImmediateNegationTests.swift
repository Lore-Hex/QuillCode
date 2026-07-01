import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentImmediateNegationTests: XCTestCase {
    func testIncidentalBareCommandMentionStillUsesModel() async throws {
        let root = try makeTempDirectory()
        let runner = fixedSayAgentRunner("Mention noted.")

        let result = try await runner.send(
            "The docs say run ls after setup.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "Mention noted.")
    }

    func testNegatedWhoamiDoesNotPreflight() async throws {
        let root = try makeTempDirectory()
        let runner = fixedSayAgentRunner("I will not run it.")

        let result = try await runner.send(
            "Do not run whoami.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "I will not run it.")
    }

    func testNegatedDiagnosticDoesNotPreflight() async throws {
        let root = try makeTempDirectory()
        let runner = fixedSayAgentRunner("I will leave disk usage alone.")

        let result = try await runner.send(
            "Please don't check disk usage.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "I will leave disk usage alone.")
    }

    func testNegatedOpenClawDiscoveryDoesNotPreflight() async throws {
        let root = try makeTempDirectory()
        let runner = fixedSayAgentRunner("I will not inspect OpenClaw.")

        let result = try await runner.send(
            "Do not check openclaw.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "I will not inspect OpenClaw.")
    }

    func testNegatedDownloadDoesNotPreflight() async throws {
        let root = try makeTempDirectory()
        let runner = fixedSayAgentRunner("I will not download it.")

        let result = try await runner.send(
            "Don't download https://example.com.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "I will not download it.")
    }

    func testNegatedFileWriteDoesNotPreflight() async throws {
        let root = try makeTempDirectory()
        let runner = fixedSayAgentRunner("I will not create a file.")

        let result = try await runner.send(
            "Do not write a file that says hello world.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "I will not create a file.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
    }

    func testDefaultMockRespectsOnlyNegatedActionRequest() async throws {
        let root = try makeTempDirectory()

        let result = try await AgentRunner().send(
            "Do not write a file that says hello world.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 0)
        XCTAssertEqual(result.thread.messages.last?.content, "Okay, I won't take that action.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.txt").path))
    }

    func testAffirmedSecondClauseStillExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Do not run whoami; run pwd.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), "pwd")
        XCTAssertTrue(result.thread.messages.last?.content.contains(root.path) == true)
    }

    func testDefaultMockUsesAffirmedActionAfterNegatedClause() async throws {
        let root = try makeTempDirectory()

        let result = try await AgentRunner().send(
            "Do not run whoami. Thanks. Run pwd.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), "pwd")
        XCTAssertTrue(result.thread.messages.last?.content.contains(root.path) == true)
    }
}
