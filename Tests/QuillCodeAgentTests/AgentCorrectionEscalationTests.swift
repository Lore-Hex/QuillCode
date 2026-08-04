import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// Cline learning #1 (docs/CLINE_TOOL_LEARNINGS.md): corrective re-prompts escalate with the
/// failure count instead of repeating the same text. The final budgeted attempt switches to a
/// directive form that forbids repeating the response and offers numbered ways out.
final class AgentCorrectionEscalationTests: XCTestCase {
    func testFirstAttemptPassesBaseThrough() {
        let base = "Please write the file."
        XCTAssertEqual(
            AgentCorrectionEscalation.escalated(base, attempt: 0, limit: 2, alternatives: ["a"]),
            base
        )
    }

    func testFinalAttemptGetsDirectivePreambleWithNumberedAlternatives() {
        let escalated = AgentCorrectionEscalation.escalated(
            "Please write the file.",
            attempt: 1,
            limit: 2,
            alternatives: ["write it now", "explain what blocked you"]
        )
        XCTAssertTrue(escalated.contains("FINAL ATTEMPT (2 of 2)"))
        XCTAssertTrue(escalated.contains("Do NOT repeat that response"))
        XCTAssertTrue(escalated.contains("(1) write it now"))
        XCTAssertTrue(escalated.contains("(2) explain what blocked you"))
        XCTAssertTrue(escalated.contains("Please write the file."))
    }

    func testSingleAttemptBudgetNeverEscalates() {
        let base = "base"
        XCTAssertEqual(
            AgentCorrectionEscalation.escalated(base, attempt: 0, limit: 1, alternatives: ["a"]),
            base
        )
    }

    // MARK: - End-to-end: the deliverable gate's second corrective is escalated

    private actor PromptRecorder {
        var prompts: [String] = []
        var steps: [AgentAction]
        init(_ steps: [AgentAction]) { self.steps = steps }
        func next(_ userMessage: String) -> AgentAction {
            prompts.append(userMessage)
            return steps.isEmpty ? .say("out of steps") : steps.removeFirst()
        }
        func recorded() -> [String] { prompts }
    }

    private struct RecordingClient: LLMClient {
        let state: PromptRecorder
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            await state.next(userMessage)
        }
    }

    func testDeliverableGateSecondCorrectiveIsDirective() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("escalation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        // Three bare "Done." says: initial + two corrective samples, then the hard failure.
        let state = PromptRecorder([.say("Done."), .say("Done."), .say("Done.")])
        let runner = AgentRunner(llm: RecordingClient(state: state))
        do {
            _ = try await runner.send(
                "Search the folders and build index.md with a table.",
                in: ChatThread(title: "t"),
                workspaceRoot: root
            )
            XCTFail("expected missingNamedDeliverable")
        } catch AgentError.missingNamedDeliverable {
            // expected
        }

        let prompts = await state.recorded()
        let correctives = prompts.filter { $0.contains("index.md") && $0 != prompts.first }
        XCTAssertGreaterThanOrEqual(correctives.count, 2)
        XCTAssertFalse(try XCTUnwrap(correctives.first).contains("FINAL ATTEMPT"))
        XCTAssertTrue(try XCTUnwrap(correctives.last).contains("FINAL ATTEMPT"))
        XCTAssertTrue(try XCTUnwrap(correctives.last).contains("host.file.write"))
    }
}
