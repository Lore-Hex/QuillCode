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
        init(_ steps: [Result<AgentAction, Error>]) { self.steps = steps }
        func next(thread: ChatThread) throws -> AgentAction {
            calls.append(thread.messages)
            guard !steps.isEmpty else { return .say("out of steps") }
            return try steps.removeFirst().get()
        }
        func recorded() -> [[ChatMessage]] { calls }
    }

    private struct ScriptedClient: LLMClient {
        let state: ScriptedState
        func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
            try await state.next(thread: thread)
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

    // MARK: - Configuration

    func testRunnerDefaultsToTheLibraryDeadline() {
        XCTAssertEqual(AgentRunner().turnDeadlineSeconds, AgentRunner.defaultTurnDeadlineSeconds)
        XCTAssertEqual(AgentRunner.defaultTurnDeadlineSeconds, 300)
    }

    func testDeadlineCanBeDisabled() {
        XCTAssertNil(AgentRunner(turnDeadlineSeconds: nil).turnDeadlineSeconds)
    }
}
