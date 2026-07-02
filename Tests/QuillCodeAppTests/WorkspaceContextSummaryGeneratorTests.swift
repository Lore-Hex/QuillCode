import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceContextSummaryGeneratorTests: XCTestCase {
    func testLLMSummaryPromptUsesVisibleMessagesAndRedactsSecretsFromResponse() async throws {
        let llm = RecordingSummaryLLM(response: "Keep the decisions.\nsk-tr-v1-secretshouldredact")
        let thread = ChatThread(title: "Long thread", messages: [
            ChatMessage(role: .user, content: "old request"),
            ChatMessage(role: .tool, content: #"{"hidden":"tool feedback"}"#),
            ChatMessage(role: .assistant, content: "old answer"),
            ChatMessage(role: .user, content: "latest request")
        ])
        let request = WorkspaceContextSummaryRequest(
            sourceTitle: thread.title,
            context: WorkspaceThreadSeedBuilder.summaryContext(from: thread),
            purpose: .compact
        )

        let summary = try await LLMWorkspaceContextSummaryGenerator(llm: llm)
            .summary(for: request)
        let prompt = await llm.lastPrompt
        let tools = await llm.lastTools

        XCTAssertEqual(tools, [])
        XCTAssertTrue(prompt.contains("old request"))
        XCTAssertTrue(prompt.contains("old answer"))
        XCTAssertTrue(prompt.contains("latest request"))
        XCTAssertFalse(prompt.contains("tool feedback"))
        XCTAssertTrue(summary.contains("Keep the decisions."))
        XCTAssertFalse(summary.contains("sk-tr-v1-secretshouldredact"))
        XCTAssertTrue(summary.contains("[redacted]"))
    }

    func testLLMSummaryRetargetsOverridableClientAtRequestedAuxiliaryModel() async throws {
        let recorder = ModelCallRecorder()
        let llm = OverridableRecordingLLM(model: "acme/flagship", recorder: recorder)

        _ = try await LLMWorkspaceContextSummaryGenerator(llm: llm)
            .summary(for: summaryRequest(modelID: "acme/tiny-mini"))

        let recordedModel = await recorder.lastModel
        XCTAssertEqual(recordedModel, "acme/tiny-mini")
    }

    func testLLMSummaryKeepsConfiguredModelWhenRequestHasNoOverride() async throws {
        let recorder = ModelCallRecorder()
        let llm = OverridableRecordingLLM(model: "acme/flagship", recorder: recorder)

        _ = try await LLMWorkspaceContextSummaryGenerator(llm: llm)
            .summary(for: summaryRequest(modelID: nil))

        let recordedModel = await recorder.lastModel
        XCTAssertEqual(recordedModel, "acme/flagship")
    }

    func testLLMSummarySurvivesNonOverridableClient() async throws {
        let llm = RecordingSummaryLLM(response: "Plain summary.")

        let summary = try await LLMWorkspaceContextSummaryGenerator(llm: llm)
            .summary(for: summaryRequest(modelID: "acme/tiny-mini"))

        XCTAssertTrue(summary.contains("Plain summary."))
    }

    private func summaryRequest(modelID: String?) -> WorkspaceContextSummaryRequest {
        let thread = ChatThread(title: "Long thread", messages: [
            ChatMessage(role: .user, content: "old request"),
            ChatMessage(role: .assistant, content: "old answer"),
            ChatMessage(role: .user, content: "latest request")
        ])
        return WorkspaceContextSummaryRequest(
            sourceTitle: thread.title,
            context: WorkspaceThreadSeedBuilder.summaryContext(from: thread),
            purpose: .compact,
            modelID: modelID
        )
    }
}

private actor ModelCallRecorder {
    private(set) var lastModel: String?

    func record(_ model: String) {
        lastModel = model
    }
}

private struct OverridableRecordingLLM: ModelOverridingLLMClient {
    var model: String
    let recorder: ModelCallRecorder

    func overridingModel(_ modelID: String) -> OverridableRecordingLLM {
        var copy = self
        copy.model = modelID
        return copy
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        await recorder.record(model)
        return .say("Summary of the important context.")
    }
}

private actor RecordingSummaryLLM: LLMClient {
    private(set) var lastPrompt = ""
    private(set) var lastTools: [ToolDefinition] = []
    var response: String

    init(response: String) {
        self.response = response
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        lastPrompt = userMessage
        lastTools = tools
        return .say(response)
    }
}
