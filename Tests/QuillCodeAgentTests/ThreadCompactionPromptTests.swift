import QuillCodeCore
@testable import QuillCodeAgent
import XCTest

final class ThreadCompactionPromptTests: XCTestCase {
    func testLLMBackedCompactorUsesBoundedCustomPromptAndIncludesTranscript() async throws {
        let llm = CapturingCompactionLLM()
        let marker = "Preserve architecture decisions and unresolved test failures."
        let compactor = ThreadCompactor.llmBacked(
            llm: llm,
            catalog: [],
            sessionModelID: "trustedrouter/fast",
            keepRecentMessages: 2,
            perMessageTokenFloor: 0,
            customPrompt: marker
        )
        var thread = ChatThread(title: "Compaction test", messages: [
            ChatMessage(role: .user, content: "first request"),
            ChatMessage(role: .assistant, content: "first answer"),
            ChatMessage(role: .user, content: "second request"),
            ChatMessage(role: .assistant, content: "second answer")
        ])

        let result = await compactor.compact(&thread)

        guard case .compacted = result else {
            return XCTFail("Expected the older messages to be compacted")
        }
        let captured = await llm.capturedPrompt()
        let prompt = try XCTUnwrap(captured)
        XCTAssertTrue(prompt.contains(marker))
        XCTAssertTrue(prompt.contains("first request"))
        XCTAssertTrue(prompt.contains("second answer"))
        XCTAssertFalse(prompt.contains("Please compact this QuillCode coding-agent thread"))
        XCTAssertEqual(thread.messages.first?.content, "custom summary")
    }

    func testCustomPromptIsBoundedBeforeSendingItToTheModel() async throws {
        let llm = CapturingCompactionLLM()
        let summarizer = LLMThreadCompactionSummarizer(
            llm: llm,
            customPrompt: String(repeating: "x", count: 20_000)
        )

        _ = try await summarizer.summarize(
            sourceTitle: "Bounded",
            olderMessages: [ChatMessage(role: .user, content: "old")],
            recentMessages: [ChatMessage(role: .assistant, content: "new")]
        )

        let captured = await llm.capturedPrompt()
        let prompt = try XCTUnwrap(captured)
        XCTAssertTrue(prompt.contains(String(repeating: "x", count: 8_000)))
        XCTAssertFalse(prompt.contains(String(repeating: "x", count: 8_001)))
    }
}

private actor CapturingCompactionLLM: LLMClient {
    private var prompt: String?

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        prompt = userMessage
        return .say("custom summary")
    }

    func capturedPrompt() -> String? { prompt }
}
