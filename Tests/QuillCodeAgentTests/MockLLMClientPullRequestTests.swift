import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class MockLLMClientPullRequestTests: XCTestCase {
    func testListPullRequestsUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "list merged pull requests limit 12",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestList.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(arguments["state"] as? String, "merged")
        XCTAssertEqual(arguments["limit"] as? Int, 12)
    }

    func testListPullRequestsDoesNotInferStateFromPartialWords() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "list pull requests mentioning openclaw",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestList.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(arguments["state"])
    }

    func testCreatePullRequestUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "create a pull request titled Add PR tool base main head feature/pr-tool",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestCreate.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["title"], "Add PR tool")
        XCTAssertEqual(arguments["base"], "main")
        XCTAssertEqual(arguments["head"], "feature/pr-tool")
    }

    func testViewPullRequestUsesReadOnlyToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "show current PR comments",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestView.name)
        XCTAssertEqual(call.argumentsJSON, "{}")
    }

    func testPullRequestChecksUsesReadOnlyToolCallWithSelector() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "check PR #42 status",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestChecks.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
    }

    func testPullRequestCheckoutUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "checkout PR #42",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestCheckout.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
    }

    func testPullRequestReviewerRequestUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "request review from alice and myorg/team-name on PR #42",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReviewers.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["add"], "alice,myorg/team-name")
    }

    func testPullRequestLabelRequestUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "label PR #42 merge-train",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestLabels.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["add"], "merge-train")
    }

    func testPullRequestCommentUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "comment on PR #42 saying Ready for review",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestComment.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["body"], "Ready for review")
    }

    func testPullRequestReviewUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "request changes on PR #42 saying Please add tests",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestReview.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["action"], "request_changes")
        XCTAssertEqual(arguments["body"], "Please add tests")
    }

    func testPullRequestMergeUsesStructuredToolCall() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "auto merge PR #42 with rebase and delete branch",
            tools: ToolRouter.definitions
        )

        guard case .tool(let call) = action else {
            return XCTFail("Expected a tool action.")
        }
        XCTAssertEqual(call.name, ToolDefinition.gitPullRequestMerge.name)
        let data = try XCTUnwrap(call.argumentsJSON.data(using: .utf8))
        let arguments = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(arguments["selector"], "42")
        XCTAssertEqual(arguments["method"], "rebase")
        XCTAssertEqual(arguments["auto"], "true")
        XCTAssertEqual(arguments["deleteBranch"], "true")
    }
}
