import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

/// A scripted LLM client whose steps either throw or return an action, recording every call's
/// thread + userMessage so tests can assert exactly what each retry request contained.
private actor ThrowingSequenceLLMState {
    enum Step {
        case action(AgentAction)
        case failure(any Error)
    }

    private var steps: [Step]
    private(set) var calls: [(userMessage: String, messages: [ChatMessage])] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func next(thread: ChatThread, userMessage: String) throws -> AgentAction {
        calls.append((userMessage, thread.messages))
        guard !steps.isEmpty else {
            return .say("out of scripted steps")
        }
        switch steps.removeFirst() {
        case .action(let action):
            return action
        case .failure(let error):
            throw error
        }
    }

    func recordedCalls() -> [(userMessage: String, messages: [ChatMessage])] { calls }
}

private struct ThrowingSequenceLLMClient: LLMClient {
    let state: ThrowingSequenceLLMState

    init(steps: [ThrowingSequenceLLMState.Step]) {
        self.state = ThrowingSequenceLLMState(steps: steps)
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try await state.next(thread: thread, userMessage: userMessage)
    }
}

final class AgentMalformedActionRecoveryTests: XCTestCase {
    private static let garbage = "，������但我��随时？？ mojibake .UseFont���/or"
    // Not parseable by AgentImmediateActionPlanner, so the LLM path is always exercised.
    private static let prompt = "summarize the current state of the repository"

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("malformed-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testOneMalformedResponseIsRepromptedAndRunSucceeds() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON(Self.garbage)),
            .action(.say("Recovered fine.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered fine.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("Self-healing: the model returned a malformed action")
        }, "durable thread must carry the self-healing notice")

        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        // The corrective request carries the garbage + correction ONLY on the transient retry thread.
        let retryMessages = calls[1].messages
        XCTAssertTrue(retryMessages.contains { $0.role == .assistant && $0.content.contains("mojibake") })
        XCTAssertTrue(calls[1].userMessage.contains("was not a valid QuillCode action JSON object"))
        // The durable transcript never contains the garbage or the correction prompt.
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("mojibake") })
        XCTAssertFalse(result.thread.messages.contains {
            $0.content.contains("was not a valid QuillCode action JSON object")
        })
    }

    func testPersistentMalformedOutputFailsAfterExactlyTwoCorrections() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON("bad1")),
            .failure(TrustedRouterAgentError.invalidActionJSON("bad2")),
            .failure(TrustedRouterAgentError.invalidActionJSON("bad3")),
        ])
        let runner = AgentRunner(llm: client)

        do {
            _ = try await runner.send(
                Self.prompt,
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory()
            )
            XCTFail("expected invalidActionJSON after correction limit")
        } catch TrustedRouterAgentError.invalidActionJSON(let text) {
            XCTAssertEqual(text, "bad3", "the LAST malformed payload should surface")
        }

        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3, "1 original + exactly 2 corrective re-prompts")
    }

    func testStreamInterruptionIsRetriedAndRunSucceeds() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(AgentStreamInterruptedError(underlying: URLError(.cancelled))),
            .action(.say("Survived the reset.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Survived the reset.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("Self-healing: the model stream was interrupted")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
        // A stream interruption is a pure resample — no corrective context is injected.
        XCTAssertFalse(calls[1].messages.contains {
            $0.content.contains("was not a valid QuillCode action JSON object")
        })
    }

    func testExhaustedStreamInterruptionsSurfaceTheUnderlyingError() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(AgentStreamInterruptedError(underlying: URLError(.networkConnectionLost))),
            .failure(AgentStreamInterruptedError(underlying: URLError(.networkConnectionLost))),
            .failure(AgentStreamInterruptedError(underlying: URLError(.cancelled))),
        ])
        let runner = AgentRunner(llm: client)

        do {
            _ = try await runner.send(
                Self.prompt,
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory()
            )
            XCTFail("expected the underlying URLError after the retry limit")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled, "the marker must unwrap to the underlying error")
        }

        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3)
    }

    func testMixedMalformedThenInterruptedRecoversWithinSharedBudget() async throws {
        // The two recovery kinds share one bounded budget — a flapping model can't get 2 + 2.
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(TrustedRouterAgentError.invalidActionJSON("bad")),
            .failure(AgentStreamInterruptedError(underlying: URLError(.networkConnectionLost))),
            .action(.say("Third time lucky.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Third time lucky.")
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3)
    }

    func testEmptyStreamingResponseIsRetriedAndRunSucceeds() async throws {
        // A clean-but-empty stream (gateway teardown before the first token, empty 200, immediate
        // [DONE]) is the streaming twin of TrustedRouterAgentError.emptyResponse and gets a resample.
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(AgentError.emptyStreamingResponse),
            .action(.say("Filled in on retry.")),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Filled in on retry.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("Self-healing: the model returned an empty response")
        })
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 2)
    }

    func testExhaustedEmptyStreamingResponsesStayFatal() async throws {
        let client = ThrowingSequenceLLMClient(steps: [
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
            .failure(AgentError.emptyStreamingResponse),
        ])
        let runner = AgentRunner(llm: client)

        do {
            _ = try await runner.send(
                Self.prompt,
                in: ChatThread(mode: .auto),
                workspaceRoot: try makeTempDirectory()
            )
            XCTFail("expected emptyStreamingResponse after the retry limit")
        } catch AgentError.emptyStreamingResponse {
            // Correct terminal error.
        }
        let calls = await client.state.recordedCalls()
        XCTAssertEqual(calls.count, 3)
    }

    func testUserStopAtBudgetExhaustionSurfacesAsCancellationNotFailure() async throws {
        // Both recovery attempts burned, then the user stops during the third call whose garbage
        // arrives after the cancel: the resolver must honor the stop (CancellationError), never
        // report a malformed-model failure for a run the user deliberately stopped.
        let started = expectation(description: "third LLM call started")
        let client = BlockingThenThrowingLLMClient(blockOnCall: 3, onBlockedCall: { started.fulfill() })
        let runner = AgentRunner(llm: client)
        let root = try makeTempDirectory()

        let prompt = Self.prompt
        let task = Task { [runner] in
            try await runner.send(prompt, in: ChatThread(mode: .auto), workspaceRoot: root)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await client.releaseBlockedCall()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // Correct: the stop wins over the exhausted-budget malformed error.
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 3)
    }

    func testCorrectiveAttemptUsageIsHarvestedOntoDurableThread() async throws {
        // Corrective re-prompts must never be invisible to spend accounting: the scratch corrective
        // run's token-usage event is harvested onto the durable thread.
        let client = ScriptedUsageStreamingLLMClient(scripts: [
            .init(text: "totally not json ���", usage: .init(promptTokens: 10, completionTokens: 5, totalTokens: 15)),
            .init(text: #"{"type":"say","text":"Recovered with usage."}"#, usage: .init(promptTokens: 20, completionTokens: 7, totalTokens: 27)),
        ])
        let runner = AgentRunner(llm: client)

        let result = try await runner.send(
            Self.prompt,
            in: ChatThread(mode: .auto),
            workspaceRoot: try makeTempDirectory()
        )

        XCTAssertEqual(result.thread.messages.last?.content, "Recovered with usage.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("malformed action")
        })
        XCTAssertTrue(
            result.thread.events.contains { $0.summary == "Model token usage" },
            "the corrective attempt's usage event must land on the durable thread"
        )
        // The corrective context itself never persists.
        XCTAssertFalse(result.thread.messages.contains { $0.content.contains("totally not json") })
    }

    func testCancelledRunDoesNotReprompt() async throws {
        let started = expectation(description: "first LLM call started")
        let client = BlockingThenThrowingLLMClient(blockOnCall: 1, onBlockedCall: { started.fulfill() })
        let runner = AgentRunner(llm: client)
        let root = try makeTempDirectory()

        let prompt = Self.prompt
        let task = Task { [runner] in
            try await runner.send(prompt, in: ChatThread(mode: .auto), workspaceRoot: root)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await client.releaseBlockedCall()

        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            // Reaching here without a second LLM call is the assertion that matters.
        }
        let callCount = await client.callCount()
        XCTAssertEqual(callCount, 1, "a cancelled run must not receive a corrective re-prompt")
    }
}

/// Throws invalidActionJSON on every call; call number `blockOnCall` first signals, then blocks until
/// released — so tests can cancel the owning task mid-call at a precise attempt and prove the
/// resolver honors the stop (instead of re-prompting, or reporting a malformed failure at exhaustion).
private actor BlockingThenThrowingLLMClientState {
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func enter() -> Int {
        calls += 1
        return calls
    }

    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private struct BlockingThenThrowingLLMClient: LLMClient {
    let state = BlockingThenThrowingLLMClientState()
    let blockOnCall: Int
    let onBlockedCall: @Sendable () -> Void

    init(blockOnCall: Int, onBlockedCall: @escaping @Sendable () -> Void) {
        self.blockOnCall = blockOnCall
        self.onBlockedCall = onBlockedCall
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        let count = await state.enter()
        if count == blockOnCall {
            onBlockedCall()
            await state.waitForRelease()
        }
        throw TrustedRouterAgentError.invalidActionJSON("garbage-attempt-\(count)")
    }

    func releaseBlockedCall() async {
        await state.release()
    }

    func callCount() async -> Int {
        await state.calls
    }
}

/// A scripted UsageStreamingLLMClient: each call streams its script's text then a usage event, so the
/// production usage-accounting path (collectStreamingAction) runs for both original and corrective
/// attempts.
private struct ScriptedUsageStreamingLLMClient: UsageStreamingLLMClient {
    struct Script: Sendable {
        var text: String
        var usage: ModelTokenUsage
    }

    private actor Progress {
        private(set) var index = 0
        func next() -> Int { defer { index += 1 }; return index }
        func count() -> Int { index }
    }

    private let scripts: [Script]
    private let progress = Progress()

    init(scripts: [Script]) {
        self.scripts = scripts
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        // Force the streaming path in tests: the resolver should never take the plain branch for a
        // UsageStreamingLLMClient.
        throw TrustedRouterAgentError.emptyResponse
    }

    func actionTextStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<String, Error> {
        throw TrustedRouterAgentError.emptyResponse
    }

    func actionEventStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        let index = await progress.next()
        let script = scripts[min(index, scripts.count - 1)]
        return AsyncThrowingStream { continuation in
            continuation.yield(.text(script.text))
            continuation.yield(.usage(script.usage))
            continuation.finish()
        }
    }
}
