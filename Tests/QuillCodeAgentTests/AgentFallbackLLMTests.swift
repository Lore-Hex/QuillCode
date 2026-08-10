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

    func testStandbyRecoveryDoesNotDisplaceEstablishedFallbackRoute() async throws {
        let root = try makeTempDirectory()
        try Data("first context".utf8).write(to: root.appendingPathComponent("input-1.txt"))
        try Data("second context".utf8).write(to: root.appendingPathComponent("input-2.txt"))
        let overrun = AgentPreActionReasoningBudgetExceededError(maximumCharacters: 6_000)
        let primary = ScriptedState(
            Self.alwaysEmpty + [.success(.tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: #"{"path":"input-2.txt"}"#
            )))]
        )
        let fallback = ScriptedState([
            .success(.tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: #"{"path":"input-1.txt"}"#
            ))),
            .failure(overrun),
            .failure(overrun),
            .failure(overrun),
            .success(.say("established fallback route finalized both files")),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            maxToolSteps: 4,
            fallbackLLM: ScriptedClient(state: fallback),
            emptyResponseRetrySleeper: ImmediateEmptyResponseRetrySleeper()
        )

        let result = try await runner.send(
            "Read input-1.txt and input-2.txt, then summarize their contents.",
            in: ChatThread(title: "t"),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 2)
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(
            result.thread.messages.last?.content,
            "established fallback route finalized both files"
        )
        XCTAssertEqual(
            result.thread.events.filter { $0.summary.contains("promoting that route") }.count,
            1,
            "the first recovered route remains established for the run"
        )
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("keeping the established route active")
        })
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()
        XCTAssertEqual(primaryCalls, 8)
        XCTAssertEqual(fallbackCalls, 5)
    }

    func testBoundedFinalizationKeepsPrimaryAfterOnePhaseInvalidAction() async throws {
        let root = try makeTempDirectory()
        let reportPath = "outputs/report.md"
        let lateResearch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.test/late-research"])
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": reportPath,
                "content": "# Report\n\nBest available evidence synthesized.\n",
            ])
        )
        let read = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": reportPath])
        )
        let primary = ScriptedState([
            .success(.tool(lateResearch)),
            .success(.tool(write)),
            .success(.tool(read)),
            .success(.say("Completed and verified outputs/report.md.")),
        ])
        let fallback = ScriptedState([.success(.say("fallback should not run"))])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            maxToolSteps: 10,
            boundedRunFinalizationAfterSeconds: 0,
            fallbackLLM: ScriptedClient(state: fallback)
        )

        let result = try await runner.send(
            "Write outputs/report.md and verify the saved output by reading it back.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(result.toolResults.map(\.ok), [true, true])
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(reportPath)),
            "# Report\n\nBest available evidence synthesized.\n"
        )
        XCTAssertFalse(result.thread.events.contains {
            $0.summary == AgentRunner.boundedFinalizationFallbackSwitchNotice
        })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("rejected a non-finalization action (tool host.web.fetch)")
        })
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()
        XCTAssertEqual(primaryCalls, 4)
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testBoundedFinalizationPromotesFallbackAfterRepeatedPhaseInvalidActions() async throws {
        let root = try makeTempDirectory()
        let reportPath = "outputs/report.md"
        let lateResearch = ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: ToolArguments.json(["url": "https://example.test/late-research"])
        )
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": reportPath,
                "content": "# Report\n\nBest available evidence synthesized.\n",
            ])
        )
        let read = ToolCall(
            name: ToolDefinition.fileRead.name,
            argumentsJSON: ToolArguments.json(["path": reportPath])
        )
        let primary = ScriptedState([
            .success(.tool(lateResearch)),
            .success(.tool(lateResearch)),
        ])
        let fallback = ScriptedState([
            .success(.tool(write)),
            .success(.tool(read)),
            .success(.say("Completed and verified outputs/report.md.")),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            maxToolSteps: 10,
            boundedRunFinalizationAfterSeconds: 0,
            fallbackLLM: ScriptedClient(state: fallback)
        )

        let result = try await runner.send(
            "Write outputs/report.md and verify the saved output by reading it back.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(result.toolResults.map(\.ok), [true, true])
        XCTAssertTrue(result.thread.events.contains {
            $0.summary == AgentRunner.boundedFinalizationFallbackSwitchNotice
        })
        let primaryCalls = await primary.calls()
        let fallbackCalls = await fallback.calls()
        XCTAssertEqual(primaryCalls, 2)
        XCTAssertEqual(fallbackCalls, 3)
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
