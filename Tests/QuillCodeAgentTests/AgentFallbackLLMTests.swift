import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// F22: when the primary model exhausts the empty-response correction budget on a step (a
/// route-quality death observed at ~1-in-6 runs on one provider while an alternate model completed
/// the same step first try), the resolver retries that step once on the fallback client instead of
/// killing the run — preserving all prior tool work in the same thread.
final class AgentFallbackLLMTests: XCTestCase {
    private struct ImmediateEmptyResponseRetrySleeper: RetrySleeper {
        func sleep(_ duration: Duration) async throws {}
    }

    private actor ScriptedState {
        var steps: [Result<AgentAction, Error>]
        private(set) var callCount = 0
        init(_ steps: [Result<AgentAction, Error>]) { self.steps = steps }
        func next() throws -> AgentAction {
            callCount += 1
            guard !steps.isEmpty else { return .say("out of steps") }
            return try steps.removeFirst().get()
        }
        func calls() -> Int { callCount }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            try await state.next()
        }
    }

    private static let alwaysEmpty: [Result<AgentAction, Error>] = [
        .failure(AgentError.emptyStreamingResponse),
        .failure(AgentError.emptyStreamingResponse),
        .failure(AgentError.emptyStreamingResponse),
        .failure(AgentError.emptyStreamingResponse),
        .failure(AgentError.emptyStreamingResponse),
        .failure(AgentError.emptyStreamingResponse),
        .failure(AgentError.emptyStreamingResponse),
    ]

    private static var exhaustedStartup: [Result<AgentAction, Error>] {
        Array(
            repeating: alwaysEmpty,
            count: AgentRunner.startupActionContinuationLimit + 1
        ).flatMap { $0 }
    }

    func testExhaustedEmptyResponsesSwitchToFallbackAndRunSucceeds() async throws {
        let primary = ScriptedState(Self.alwaysEmpty)
        let fallback = ScriptedState([.success(.say("fallback finished the step"))])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            fallbackLLM: ScriptedClient(state: fallback),
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            "summarize the current state of the repository",
            in: ChatThread(title: "t"),
            workspaceRoot: FileManager.default.temporaryDirectory
        )

        XCTAssertTrue(result.thread.messages.contains { $0.content.contains("fallback finished the step") })
        XCTAssertTrue(result.thread.events.contains { $0.summary.contains("switching to the fallback model") })
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()
        XCTAssertEqual(primaryCalls, 7, "primary gets its full budget first")
        XCTAssertEqual(fallbackCalls, 1)
    }

    func testSuccessfulFallbackRemainsActiveForRestOfRun() async throws {
        let root = try makeTempDirectory()
        try Data("grounded context".utf8).write(to: root.appendingPathComponent("input.txt"))
        let primary = ScriptedState(Self.alwaysEmpty)
        let fallback = ScriptedState([
            .success(.tool(.init(
                name: "host.file.read",
                argumentsJSON: #"{"path":"input.txt"}"#
            ))),
            .success(.say("fallback summarized the grounded context")),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            maxToolSteps: 3,
            fallbackLLM: ScriptedClient(state: fallback),
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            "Read input.txt, then summarize its contents.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1)
        XCTAssertTrue(result.toolResults[0].ok, result.toolResults[0].error ?? "")
        XCTAssertEqual(result.thread.messages.last?.content, "fallback summarized the grounded context")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("promoting that route")
        })
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()
        XCTAssertEqual(primaryCalls, 7, "the failed primary must not be retried after recovery")
        XCTAssertEqual(fallbackCalls, 2, "fallback owns both the tool action and finalization")
    }

    func testPromotedFallbackFailureCanRecoverThroughPriorRoute() async throws {
        let root = try makeTempDirectory()
        try Data("grounded context".utf8).write(to: root.appendingPathComponent("input.txt"))
        let overrun = AgentPreActionReasoningBudgetExceededError(maximumCharacters: 6_000)
        let primary = ScriptedState(
            Self.alwaysEmpty + [.success(.say("selected route rescued finalization"))]
        )
        let fallback = ScriptedState([
            .success(.tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: #"{"path":"input.txt"}"#
            ))),
            .failure(overrun),
            .failure(overrun),
            .failure(overrun),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            maxToolSteps: 3,
            fallbackLLM: ScriptedClient(state: fallback),
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            "Read input.txt, then summarize its contents.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.thread.messages.last?.content, "selected route rescued finalization")
        XCTAssertEqual(
            result.thread.events.filter { $0.summary.contains("promoting that route") }.count,
            2,
            "each route is promoted only after it successfully recovers the active step"
        )
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()
        XCTAssertEqual(primaryCalls, 8)
        XCTAssertEqual(fallbackCalls, 4)
    }

    func testFallbackAlsoFailingStaysFatalAcrossBoundedStartupRecovery() async {
        let primary = ScriptedState(Self.exhaustedStartup)
        let fallback = ScriptedState(Self.exhaustedStartup)
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            fallbackLLM: ScriptedClient(state: fallback),
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )
        do {
            _ = try await runner.send(
                "summarize the current state of the repository",
                in: ChatThread(title: "t"),
                workspaceRoot: FileManager.default.temporaryDirectory
            )
            XCTFail("expected the exhaustion to stay fatal")
        } catch AgentError.emptyStreamingResponse {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()
        let expectedCalls = Self.alwaysEmpty.count * (AgentRunner.startupActionContinuationLimit + 1)
        XCTAssertEqual(primaryCalls, expectedCalls)
        XCTAssertEqual(fallbackCalls, expectedCalls)
    }

    func testNoFallbackConfiguredStaysFatalAcrossBoundedStartupRecovery() async {
        let primary = ScriptedState(Self.exhaustedStartup)
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )
        do {
            _ = try await runner.send(
                "summarize the current state of the repository",
                in: ChatThread(title: "t"),
                workspaceRoot: FileManager.default.temporaryDirectory
            )
            XCTFail("expected fatal exhaustion")
        } catch AgentError.emptyStreamingResponse {
            // expected — nil fallback preserves existing behavior exactly
        } catch {
            XCTFail("wrong error: \(error)")
        }
        let primaryCalls = await primary.calls()
        XCTAssertEqual(
            primaryCalls,
            Self.alwaysEmpty.count * (AgentRunner.startupActionContinuationLimit + 1)
        )
    }
}
