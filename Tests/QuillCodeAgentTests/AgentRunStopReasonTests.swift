import XCTest
import QuillCodeCore
import QuillCodeTools
import QuillCodeAgent

/// Returns a different tool call each time, so the run never trips the repeated-call finalizer and
/// instead runs its full tool-step budget — exercising the ceiling-exhaustion path.
private final class VaryingToolLLMClient: LLMClient, @unchecked Sendable {
    private var counter = 0
    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        counter += 1
        return .tool(ToolCall(name: "host.file.read", argumentsJSON: ToolArguments.json(["path": "missing-\(counter).txt"])))
    }
}

final class AgentRunStopReasonTests: XCTestCase {
    private var root: URL { FileManager.default.temporaryDirectory }

    func testCeilingExhaustionIsHonestlyLabeled() async throws {
        let runner = AgentRunner(
            llm: VaryingToolLLMClient(),
            toolExecutionOverride: { _, _ in ToolResult(ok: false, error: "missing") },
            maxToolSteps: 2
        )
        let result = try await runner.send("go", in: ChatThread(title: "T", messages: [], events: []), workspaceRoot: root)

        // The run gave up at its budget — not a genuine finish.
        XCTAssertEqual(result.stopReason, .toolStepCeilingExhausted(limit: 2))
        XCTAssertTrue(
            result.thread.events.contains { $0.kind == .notice && $0.summary.contains("step tool limit") },
            "expected an honest ceiling notice; got \(result.thread.events.map(\.summary))"
        )
    }

    func testGenuineFinishIsMarkedFinished() async throws {
        let runner = AgentRunner(llm: FixedSayLLMClient(message: "All done."))
        let result = try await runner.send("go", in: ChatThread(title: "T", messages: [], events: []), workspaceRoot: root)

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertFalse(result.thread.events.contains { $0.kind == .notice && $0.summary.contains("step tool limit") })
    }
}
