import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class AgentPreActionReasoningBudgetTests: XCTestCase {
    func testDeltaReasoningOverBudgetThrowsBeforeAction() async {
        let stream = eventStream([
            .reasoning("1234"),
            .reasoning("5678"),
            .text(#"{"type":"say","text":"too late"}"#),
        ])
        let guarded = AgentPreActionReasoningBudget.enforcing(maximumCharacters: 6, on: stream)

        do {
            for try await _ in guarded {}
            XCTFail("expected the reasoning budget to fire")
        } catch let error as AgentPreActionReasoningBudgetExceededError {
            XCTAssertEqual(error.maximumCharacters, 6)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testGrowingReasoningSnapshotsAreNotDoubleCounted() async throws {
        let events: [AgentTextStreamEvent] = [
            .reasoning("plan"),
            .reasoning("planning"),
            .reasoning("planning"),
            .text(#"{"type":"say","text":"done"}"#),
        ]
        let guarded = AgentPreActionReasoningBudget.enforcing(maximumCharacters: 8, on: eventStream(events))

        var collected: [AgentTextStreamEvent] = []
        for try await event in guarded { collected.append(event) }
        XCTAssertEqual(collected, events)
    }

    func testReasoningAfterActionStartsDoesNotTripBudget() async throws {
        let events: [AgentTextStreamEvent] = [
            .reasoning("1234"),
            .text(#"{"type":"say","#),
            .reasoning("this provider-specific fragment is ignored by the pre-action guard"),
            .text(#""text":"done"}"#),
        ]
        let guarded = AgentPreActionReasoningBudget.enforcing(maximumCharacters: 4, on: eventStream(events))

        var collected: [AgentTextStreamEvent] = []
        for try await event in guarded { collected.append(event) }
        XCTAssertEqual(collected, events)
    }

    func testBudgetOverrunUsesBoundedCorrectivePath() async throws {
        let state = ScriptedState([
            .failure(AgentPreActionReasoningBudgetExceededError(maximumCharacters: 12_000)),
            .success(.say("recovered")),
        ])
        let result = try await AgentRunner(llm: ScriptedClient(state: state)).send(
            "Create an interview guide for our ICP.",
            in: ChatThread(title: "t"),
            workspaceRoot: FileManager.default.temporaryDirectory
        )

        XCTAssertTrue(result.thread.messages.contains { $0.content == "recovered" })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let calls = await state.recorded()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].contains {
            $0.role == .user && $0.content.contains("ask one focused question")
        })
    }

    func testLongReasoningAfterFirstToolActionIsAllowed() async throws {
        let root = try makeTempDirectory()
        let inputs = root.appendingPathComponent("inputs", isDirectory: true)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try Data("LedgerLoop context".utf8).write(to: inputs.appendingPathComponent("context.md"))

        let state = UsageStreamSequenceState([
            [
                .text(#"{"type":"tool","name":"host.file.read","arguments":{"path":"inputs/context.md"}}"#),
            ],
            [
                .reasoning(String(repeating: "synthesis ", count: 1_400)),
                .text(#"{"type":"say","text":"Synthesis complete."}"#),
            ],
        ])
        let result = try await AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            preActionReasoningCharacterLimit: 12_000
        ).send(
            "Read inputs/context.md and synthesize it.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(result.thread.messages.last?.content, "Synthesis complete.")
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 2)
    }

    func testReasoningBudgetRetightensAfterSuccessfulWrite() async throws {
        let root = try makeTempDirectory()
        let state = UsageStreamSequenceState([
            [
                .text(#"{"type":"tool","name":"host.file.write","arguments":{"path":"output.txt","content":"done"}}"#),
            ],
            [
                .reasoning(String(repeating: "verify ", count: 2_000)),
                .text(#"{"type":"say","text":"too late"}"#),
            ],
            [
                .reasoning(String(repeating: "still planning ", count: 200)),
                .text(#"{"type":"say","text":"still too late"}"#),
            ],
            [
                .text(#"{"type":"say","text":"Verified output.txt."}"#),
            ],
        ])
        let result = try await AgentRunner(
            llm: UsageStreamSequenceClient(state: state),
            preActionReasoningCharacterLimit: 12_000
        ).send(
            "Create output.txt.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Verified output.txt.")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("pre-action reasoning budget")
        })
        let requestCount = await state.requestCount()
        XCTAssertEqual(requestCount, 4)
    }

    func testRunnerDefaultsToReasoningBudgetAndCanDisableIt() {
        XCTAssertEqual(
            AgentRunner().preActionReasoningCharacterLimit,
            AgentRunner.defaultPreActionReasoningCharacterLimit
        )
        XCTAssertEqual(
            AgentRunner().interActionReasoningCharacterLimit,
            AgentRunner.defaultInterActionReasoningCharacterLimit
        )
        XCTAssertNil(AgentRunner(preActionReasoningCharacterLimit: nil).preActionReasoningCharacterLimit)
        XCTAssertNil(AgentRunner(interActionReasoningCharacterLimit: nil).interActionReasoningCharacterLimit)
    }

    private func eventStream(
        _ events: [AgentTextStreamEvent]
    ) -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    private actor ScriptedState {
        var steps: [Result<AgentAction, Error>]
        private(set) var calls: [[ChatMessage]] = []

        init(_ steps: [Result<AgentAction, Error>]) {
            self.steps = steps
        }

        func next(thread: ChatThread) throws -> AgentAction {
            calls.append(thread.messages)
            guard !steps.isEmpty else { return .say("out of steps") }
            return try steps.removeFirst().get()
        }

        func recorded() -> [[ChatMessage]] { calls }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState

        func nextAction(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AgentAction {
            try await state.next(thread: thread)
        }
    }

    private actor UsageStreamSequenceState {
        private var streams: [[AgentTextStreamEvent]]
        private var requests = 0

        init(_ streams: [[AgentTextStreamEvent]]) {
            self.streams = streams
        }

        func next() -> [AgentTextStreamEvent] {
            requests += 1
            guard !streams.isEmpty else { return [] }
            return streams.removeFirst()
        }

        func requestCount() -> Int { requests }
    }

    private struct UsageStreamSequenceClient: UsageStreamingLLMClient {
        let state: UsageStreamSequenceState

        func nextAction(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AgentAction {
            throw AgentError.emptyStreamingResponse
        }

        func actionTextStream(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AsyncThrowingStream<String, Error> {
            throw AgentError.emptyStreamingResponse
        }

        func actionEventStream(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
            let events = await state.next()
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
}
