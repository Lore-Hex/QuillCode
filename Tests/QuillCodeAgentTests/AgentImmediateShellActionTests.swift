import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentImmediateShellActionTests: XCTestCase {
    func testRunWhoamiExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("run whoami", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
    }

    func testWhoamiQuestionExecutesImmediatelyWithoutConfirmationLoop() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("whoami?", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertTrue(result.thread.messages.last?.content.hasPrefix("You are `") == true)
        XCTAssertNoAssistantMessageContains("I'll run", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), "whoami")
    }

    func testDiskUsageQuestionExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("How much hd?", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), expectedDiskUsageCommand)
        XCTAssertNoAssistantMessageContains("I'll check", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testOpenClawDiscoveryExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send(
            "Do you have openclaw?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), expectedOpenClawDiscoveryCommand)
        XCTAssertNoAssistantMessageContains("I'll check", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testOpenClawDiscoveryDoesNotDependOnProviderKnowledge() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()
        let result = try await runner.send("Do you have openclaw?", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), expectedOpenClawDiscoveryCommand)
        XCTAssertEqual(result.thread.messages.last?.content, "openclaw is not installed or is not on PATH.")
    }

    func testDiskUsageQuestionDoesNotDependOnProviderKnowledge() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()
        let result = try await runner.send("How much hd?", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), expectedDiskUsageCommand)
        XCTAssertNoAssistantMessageContains("I'll check", in: result)
    }

    func testCurrentDirectoryQuestionExecutesImmediatelyWithoutProviderRoundTrip() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Can you show me the current directory?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), "pwd")
        XCTAssertTrue(result.thread.messages.last?.content.contains(root.path) == true)
        XCTAssertNoAssistantMessageContains("I'll show", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testDownloadDomainExecutesImmediatelyWithWorkspaceBoundedPath() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(toolExecutionOverride: { @Sendable call, _ in
            Self.successfulDownloadExecution(call: call)
        })

        let result = try await runner.send(
            "Can you download LinkedIn.com?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(
            try queuedShellCommand(in: result),
            expectedDownloadCommand(url: "https://LinkedIn.com", outputPath: "downloads/linkedin.com.html")
        )
        XCTAssertEqual(result.thread.messages.last?.content, "Downloaded to `downloads/linkedin.com.html`.")
        XCTAssertNoAssistantMessageContains("I'll download", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testDownloadURLIntoExplicitPathUsesRequestedPath() async throws {
        let root = try makeTempDirectory()
        let runner = AgentRunner(toolExecutionOverride: { @Sendable call, _ in
            Self.successfulDownloadExecution(call: call)
        })

        let result = try await runner.send(
            "Download https://example.com into `downloads/example.html` in this workspace.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(
            try queuedShellCommand(in: result),
            expectedDownloadCommand(url: "https://example.com", outputPath: "downloads/example.html")
        )
        XCTAssertEqual(result.thread.messages.last?.content, "Downloaded to `downloads/example.html`.")
        XCTAssertNoAssistantMessageContains("I'll download", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testBacktickCommandDoesNotBecomeEmptyToolCall() async throws {
        let root = try makeTempDirectory()
        let result = try await AgentRunner().send("Run `pwd`", in: ChatThread(mode: .auto), workspaceRoot: root)

        try assertSingleSuccessfulToolResult(in: result)
    }

    func testPoliteDoItNowBacktickCommandExecutesImmediately() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Please run `printf quillcode_now_smoke` now and report the output.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), "printf quillcode_now_smoke")
        XCTAssertEqual(result.thread.messages.last?.content, "Output:\nquillcode_now_smoke")
        XCTAssertNoAssistantMessageContains("I'll run", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testPoliteBareCommandExecutesImmediatelyWithoutProviderRoundTrip() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "Can you run printf quillcode_polite_smoke?",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), "printf quillcode_polite_smoke")
        XCTAssertEqual(result.thread.messages.last?.content, "Output:\nquillcode_polite_smoke")
        XCTAssertNoAssistantMessageContains("I'll run", in: result)
        XCTAssertNoAssistantMessageContains("No shell command was specified", in: result)
    }

    func testOpenClawFindRequestKeepsAvailabilityDiagnosticPriority() async throws {
        let root = try makeTempDirectory()
        let runner = preflightFailingAgentRunner()

        let result = try await runner.send(
            "find openclaw",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        try assertSingleSuccessfulToolResult(in: result)
        XCTAssertEqual(try queuedShellCommand(in: result), expectedOpenClawDiscoveryCommand)
    }

    private static func successfulDownloadExecution(call: ToolCall) -> ToolResult? {
        guard call.name == ToolDefinition.shellRun.name else { return nil }
        return ToolResult(
            ok: true,
            stdout: "-rw-r--r--  1 mock  staff  42K downloads/linkedin.com.html\n",
            stderr: "",
            exitCode: 0
        )
    }
}
