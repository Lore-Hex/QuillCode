import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class MockLLMClientMultiFileArtifactTests: XCTestCase {
    func testTeamActionBriefStartsByReadingResearchFile() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "Create the team action brief from `notes/research.md` and `notes/risks.md`.",
            tools: ToolRouter.definitions
        )

        let call = try XCTUnwrap(action.toolCall)
        XCTAssertEqual(call.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(call.argumentsJSON).string("path"), "notes/research.md")
    }

    func testTeamActionBriefContinuesThroughSecondReadAndWrite() async throws {
        let user = ChatMessage(
            role: .user,
            content: "Create the team action brief from `notes/research.md` and `notes/risks.md`."
        )
        let researchRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "notes/research.md"])
        )
        let afterResearch = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(
                    for: researchRead,
                    stdout: "Customers asked for QuillCloud relay reliability."
                )
            ]
        )

        let secondAction = try await MockLLMClient().nextAction(
            thread: afterResearch,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let secondCall = try XCTUnwrap(secondAction.toolCall)
        XCTAssertEqual(secondCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(secondCall.argumentsJSON).string("path"), "notes/risks.md")

        let risksRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "notes/risks.md"])
        )
        let afterRisks = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(
                    for: researchRead,
                    stdout: "Customers asked for QuillCloud relay reliability."
                ),
                try toolFeedbackMessage(for: risksRead, stdout: "The top risk is pairing fallback.")
            ]
        )

        let writeAction = try await MockLLMClient().nextAction(
            thread: afterRisks,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let writeCall = try XCTUnwrap(writeAction.toolCall)
        XCTAssertEqual(writeCall.name, ToolDefinition.fileWrite.name)
        let writeArguments = try ToolArguments(writeCall.argumentsJSON)
        XCTAssertEqual(writeArguments.string("path"), "team-action-brief.md")
        XCTAssertTrue(writeArguments.string("content")?.contains("QuillCloud relay reliability") == true)
        XCTAssertTrue(writeArguments.string("content")?.contains("pairing fallback") == true)

        let writeFeedback = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "team-action-brief.md"])
        )
        let afterWrite = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: writeFeedback, stdout: "wrote team-action-brief.md")
            ]
        )
        let finalAction = try await MockLLMClient().nextAction(
            thread: afterWrite,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        guard case .say(let finalAnswer) = finalAction else {
            return XCTFail("Expected a final answer after the write completes.")
        }
        XCTAssertEqual(
            finalAnswer,
            "Created `team-action-brief.md` from `notes/research.md` and `notes/risks.md`."
        )
    }

    func testAllHandsEmailStartsByReadingOrgChangesDeck() async throws {
        let action = try await MockLLMClient().nextAction(
            thread: ChatThread(mode: .auto),
            userMessage: "Draft the CEO all-hands email announcing the reorg from `org-changes.pptx` and the answers in `reorg-qa`, covering the eight hardest questions.",
            tools: ToolRouter.definitions
        )

        let call = try XCTUnwrap(action.toolCall)
        XCTAssertEqual(call.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(call.argumentsJSON).string("path"), "org-changes.pptx")
    }

    func testAllHandsEmailReadsQANotesThenWritesDraft() async throws {
        let user = ChatMessage(
            role: .user,
            content: "Draft the CEO all-hands email announcing the reorg from `org-changes.pptx` and the answers in `reorg-qa`, covering the eight hardest questions."
        )
        let orgRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "org-changes.pptx"])
        )
        let afterOrgRead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(
                    for: orgRead,
                    stdout: "Product Operations moves under Engineering."
                )
            ]
        )

        let qaAction = try await MockLLMClient().nextAction(
            thread: afterOrgRead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let qaCall = try XCTUnwrap(qaAction.toolCall)
        XCTAssertEqual(qaCall.name, ToolDefinition.fileRead.name)
        XCTAssertEqual(try ToolArguments(qaCall.argumentsJSON).string("path"), "reorg-qa/hardest-questions.md")

        let qaRead = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": "reorg-qa/hardest-questions.md"])
        )
        let afterQARead = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: orgRead, stdout: "Product Operations moves under Engineering."),
                try toolFeedbackMessage(for: qaRead, stdout: "1. Why now? 2. Are there layoffs?")
            ]
        )

        let writeAction = try await MockLLMClient().nextAction(
            thread: afterQARead,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        let writeCall = try XCTUnwrap(writeAction.toolCall)
        XCTAssertEqual(writeCall.name, ToolDefinition.fileWrite.name)
        let writeArguments = try ToolArguments(writeCall.argumentsJSON)
        XCTAssertEqual(writeArguments.string("path"), "ceo-reorg-all-hands-email.md")
        XCTAssertTrue(writeArguments.string("content")?.contains("Product Operations moves under Engineering") == true)
        XCTAssertTrue(writeArguments.string("content")?.contains("8. Where do questions go?") == true)

        let writeFeedback = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json(["path": "ceo-reorg-all-hands-email.md"])
        )
        let afterWrite = ChatThread(
            mode: .auto,
            messages: [
                user,
                try toolFeedbackMessage(for: writeFeedback, stdout: "wrote ceo-reorg-all-hands-email.md")
            ]
        )
        let finalAction = try await MockLLMClient().nextAction(
            thread: afterWrite,
            userMessage: user.content,
            tools: ToolRouter.definitions
        )
        guard case .say(let finalAnswer) = finalAction else {
            return XCTFail("Expected a final answer after the all-hands email write completes.")
        }
        XCTAssertEqual(
            finalAnswer,
            "Created `ceo-reorg-all-hands-email.md` from `org-changes.pptx` and `reorg-qa/hardest-questions.md`."
        )
    }

    private func toolFeedbackMessage(for call: ToolCall, stdout: String) throws -> ChatMessage {
        let feedback = AgentToolFeedback(
            toolCall: call,
            result: ToolResult(ok: true, stdout: stdout)
        )
        return ChatMessage(role: .tool, content: try JSONHelpers.encodePretty(feedback))
    }
}

private extension AgentAction {
    var toolCall: ToolCall? {
        guard case .tool(let call) = self else { return nil }
        return call
    }
}
