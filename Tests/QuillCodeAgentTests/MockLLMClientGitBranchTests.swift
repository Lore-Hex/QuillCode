import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class MockLLMClientGitBranchTests: XCTestCase {
    func testListBranchesUsesStructuredReadTool() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "list git branches",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitBranchList.name)
        XCTAssertEqual(call.argumentsJSON, "{}")
    }

    func testSwitchBranchUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "switch to branch feature/quill",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(call.name, ToolDefinition.gitBranchSwitch.name)
        XCTAssertEqual(arguments.string("branch"), "feature/quill")
        XCTAssertNil(arguments.bool("create"))
    }

    func testCreateBranchUsesStructuredToolCallWithStartPoint() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "create branch feature/quill from origin/main",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        let arguments = try ToolArguments(call.argumentsJSON)
        XCTAssertEqual(call.name, ToolDefinition.gitBranchSwitch.name)
        XCTAssertEqual(arguments.string("branch"), "feature/quill")
        XCTAssertEqual(arguments.bool("create"), true)
        XCTAssertEqual(arguments.string("startPoint"), "origin/main")
    }
}
