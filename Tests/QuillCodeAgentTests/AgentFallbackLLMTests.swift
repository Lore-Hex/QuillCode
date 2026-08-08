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
    ]

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
        XCTAssertEqual(primaryCalls, 3, "primary gets its full budget first")
        XCTAssertEqual(fallbackCalls, 1)
    }

    func testFallbackAlsoFailingStaysFatalAndBounded() async {
        let primary = ScriptedState(Self.alwaysEmpty)
        let fallback = ScriptedState(Self.alwaysEmpty + Self.alwaysEmpty)
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
        let fallbackCalls = await fallback.calls()
        XCTAssertEqual(fallbackCalls, 3, "fallback gets ONE fresh budget, never loops")
    }

    func testNoFallbackConfiguredKeepsTodaysFatalBehavior() async {
        let primary = ScriptedState(Self.alwaysEmpty)
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
    }
}
