import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// F20: a reasoner model can stream "thinking" indefinitely without ever completing an action —
/// no terminal say, so the phrase guards never see it (live: 27k log lines classifying imaginary
/// files on a 13-file folder sort, killed only by the 25-minute process timeout). The defense is a
/// wall-clock turn deadline on the stream plus the bounded corrective re-prompt.
final class AgentTurnDeadlineTests: XCTestCase {
    // MARK: - Stream wrapper

    func testElementsPassThroughBeforeDeadline() async throws {
        let inner = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("hello ")
            continuation.yield("world")
            continuation.finish()
        }
        let wrapped = AgentTurnDeadline.enforcing(seconds: 30, on: inner)
        var collected = ""
        for try await chunk in wrapped { collected += chunk }
        XCTAssertEqual(collected, "hello world")
    }

    func testNeverEndingStreamHitsTheDeadline() async {
        // A stream that yields one chunk and then hangs forever — the spiral shape.
        let inner = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("thinking…")
            // never finishes
        }
        let wrapped = AgentTurnDeadline.enforcing(seconds: 0.2, on: inner)
        do {
            for try await _ in wrapped {}
            XCTFail("expected the turn deadline to fire")
        } catch let overrun as AgentTurnDeadlineExceededError {
            XCTAssertEqual(Int(overrun.seconds * 10), 2)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testStreamErrorsPropagateUnchangedBeforeDeadline() async {
        struct Boom: Error {}
        let inner = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish(throwing: Boom())
        }
        let wrapped = AgentTurnDeadline.enforcing(seconds: 30, on: inner)
        do {
            for try await _ in wrapped {}
            XCTFail("expected the inner error")
        } catch is Boom {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Resolver recovery

    private actor ScriptedState {
        var steps: [Result<AgentAction, Error>]
        private(set) var calls: [[ChatMessage]] = []
        private(set) var userMessages: [String] = []
        init(_ steps: [Result<AgentAction, Error>]) { self.steps = steps }
        func next(thread: ChatThread, userMessage: String) throws -> AgentAction {
            calls.append(thread.messages)
            userMessages.append(userMessage)
            guard !steps.isEmpty else { return .say("out of steps") }
            return try steps.removeFirst().get()
        }
        func recorded() -> [[ChatMessage]] { calls }
        func recordedUserMessages() -> [String] { userMessages }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            try await state.next(thread: thread, userMessage: userMessage)
        }
    }

    private actor BoundaryState {
        private var callCount = 0

        func next() async throws -> AgentAction {
            callCount += 1
            switch callCount {
            case 1:
                try await Task.sleep(nanoseconds: 300_000_000)
                throw AgentTurnDeadlineExceededError(seconds: 300)
            case 2:
                return .tool(ToolCall(
                    name: ToolDefinition.fileWrite.name,
                    argumentsJSON: ToolArguments.json([
                        "path": "outputs/report.md",
                        "content": "# Final report\n\nVerified findings.\n",
                    ])
                ))
            case 3:
                return .tool(ToolCall(
                    name: ToolDefinition.fileRead.name,
                    argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
                ))
            default:
                return .say("Completed the report.")
            }
        }
    }

    private struct BoundaryClient: LLMClient {
        let state: BoundaryState

        func nextAction(
            thread: ChatThread,
            userMessage: String,
            tools: [ToolDefinition]
        ) async throws -> AgentAction {
            try await state.next()
        }
    }

    func testDeadlineOverrunGetsOneCorrectiveAttemptAndRunSucceeds() async throws {
        let state = ScriptedState([
            .failure(AgentTurnDeadlineExceededError(seconds: 300)),
            .success(.say("recovered and finished")),
        ])
        let runner = AgentRunner(llm: ScriptedClient(state: state))
        let thread = ChatThread(title: "t")

        let result = try await runner.send(
            "summarize the current state of the repository",
            in: thread,
            workspaceRoot: FileManager.default.temporaryDirectory
        )

        XCTAssertTrue(result.thread.messages.contains { $0.content.contains("recovered and finished") })
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("reasoned past the turn deadline")
        })
        // The corrective sample must carry the stop-planning nudge.
        let calls = await state.recorded()
        XCTAssertEqual(calls.count, 2)
        XCTAssertTrue(calls[1].contains {
            $0.role == .user && $0.content.contains("Stop planning")
        })
    }

    func testPersistentOverrunFailsAfterTheSharedBudget() async {
        let state = ScriptedState([
            .failure(AgentTurnDeadlineExceededError(seconds: 300)),
            .failure(AgentTurnDeadlineExceededError(seconds: 300)),
            .failure(AgentTurnDeadlineExceededError(seconds: 300)),
        ])
        let runner = AgentRunner(llm: ScriptedClient(state: state))
        do {
            _ = try await runner.send(
                "summarize the current state of the repository",
                in: ChatThread(title: "t"),
                workspaceRoot: FileManager.default.temporaryDirectory
            )
            XCTFail("expected the overrun to surface after the correction budget")
        } catch is AgentTurnDeadlineExceededError {
            // expected: bounded, then honest failure
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testBoundedFinalizationDeadlineImmediatelySwitchesToFallback() async throws {
        let primary = ScriptedState([
            .failure(AgentTurnDeadlineExceededError(seconds: 60)),
        ])
        let fallback = ScriptedState([
            .success(.say("fallback completed the correction")),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            fallbackLLM: ScriptedClient(state: fallback)
        )
        var thread = ChatThread(title: "bounded fallback")

        let action = try await runner.nextAction(
            thread: &thread,
            userMessage: "Write outputs/report.md.",
            tools: [],
            workspaceRoot: FileManager.default.temporaryDirectory,
            onProgress: nil,
            injectedCorrection: "Write the corrected report to outputs/report.md now.",
            reasoningBudgetPhase: .boundedFinalization
        )

        XCTAssertEqual(action, .say("fallback completed the correction"))
        let primaryCalls = await primary.recorded()
        let fallbackCalls = await fallback.recorded()
        XCTAssertEqual(primaryCalls.count, 1)
        XCTAssertEqual(fallbackCalls.count, 1)
        XCTAssertTrue(thread.events.contains {
            $0.summary == AgentRunner.turnDeadlineFallbackSwitchNotice
        })
        let fallbackUserMessages = await fallback.recordedUserMessages()
        XCTAssertTrue(fallbackUserMessages[0].contains("immediately preceding corrective instruction"))
    }

    func testBoundedFinalizationDeadlineDoesNotRestartAfterBothRoutesExhaust() async {
        let primary = ScriptedState([
            .failure(AgentTurnDeadlineExceededError(seconds: 60)),
        ])
        let fallback = ScriptedState([
            .failure(AgentTurnDeadlineExceededError(seconds: 60)),
            .failure(AgentTurnDeadlineExceededError(seconds: 60)),
        ])
        let runner = AgentRunner(
            llm: ScriptedClient(state: primary),
            boundedRunFinalizationAfterSeconds: 0,
            fallbackLLM: ScriptedClient(state: fallback)
        )

        do {
            _ = try await runner.send(
                "Write outputs/report.md.",
                in: ChatThread(mode: .auto),
                workspaceRoot: FileManager.default.temporaryDirectory
            )
            XCTFail("expected both exhausted routes to surface the deadline")
        } catch is AgentTurnDeadlineExceededError {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }

        let primaryCalls = await primary.recorded()
        let fallbackCalls = await fallback.recorded()
        XCTAssertEqual(primaryCalls.count, 1)
        XCTAssertEqual(fallbackCalls.count, 2)
    }

    func testHostBoundaryEntersFinalizationWithoutPriorToolWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = AgentRunner(
            llm: BoundaryClient(state: BoundaryState()),
            maxToolSteps: 6,
            boundedRunFinalizationAfterSeconds: 0.2
        )

        let result = try await runner.send(
            "Write outputs/report.md and read it back.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md")),
            "# Final report\n\nVerified findings.\n"
        )
        XCTAssertEqual(result.thread.messages.last?.content, "Completed the report.")
        XCTAssertTrue(result.thread.events.contains {
            $0.summary.contains("moved early into bounded finalization")
        })
    }

    // MARK: - Configuration

    func testRunnerDefaultsToTheLibraryDeadline() {
        XCTAssertEqual(AgentRunner().turnDeadlineSeconds, AgentRunner.defaultTurnDeadlineSeconds)
        XCTAssertEqual(AgentRunner.defaultTurnDeadlineSeconds, 300)
    }

    func testDeadlineCanBeDisabled() {
        XCTAssertNil(AgentRunner(turnDeadlineSeconds: nil).turnDeadlineSeconds)
    }

    func testPreFinalizationDeadlineUsesRemainingHostBudget() {
        XCTAssertEqual(
            AgentBoundedRunFinalizationGate.preFinalizationTurnDeadlineSeconds(
                remainingSeconds: 45,
                configuredTurnDeadlineSeconds: 300
            ),
            45
        )
        XCTAssertEqual(
            AgentBoundedRunFinalizationGate.preFinalizationTurnDeadlineSeconds(
                remainingSeconds: 120,
                configuredTurnDeadlineSeconds: 60
            ),
            60
        )
        XCTAssertEqual(
            AgentBoundedRunFinalizationGate.preFinalizationTurnDeadlineSeconds(
                remainingSeconds: 30,
                configuredTurnDeadlineSeconds: nil
            ),
            30
        )
        XCTAssertNil(
            AgentBoundedRunFinalizationGate.preFinalizationTurnDeadlineSeconds(
                remainingSeconds: 0,
                configuredTurnDeadlineSeconds: 300
            )
        )
    }

    func testExpiredFinalizationDeadlineStopsResolverBeforeSampling() async {
        let state = ScriptedState([.success(.say("must not be sampled"))])
        let runner = AgentRunner(llm: ScriptedClient(state: state))
        var thread = ChatThread(title: "expired")

        do {
            _ = try await runner.nextAction(
                thread: &thread,
                userMessage: "write outputs/report.md",
                tools: [],
                workspaceRoot: FileManager.default.temporaryDirectory,
                onProgress: nil,
                absoluteTurnDeadline: Date(timeIntervalSinceNow: -1)
            )
            XCTFail("expected the expired host deadline to surface")
        } catch is AgentTurnDeadlineExceededError {
            let calls = await state.recorded()
            XCTAssertTrue(calls.isEmpty)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
