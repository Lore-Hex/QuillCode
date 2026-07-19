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

    func testCancelledRunDoesNotReprompt() async throws {
        let started = expectation(description: "first LLM call started")
        let client = BlockingThenThrowingLLMClient(onFirstCall: { started.fulfill() })
        let runner = AgentRunner(llm: client)
        let root = try makeTempDirectory()

        let prompt = Self.prompt
        let task = Task { [runner] in
            try await runner.send(prompt, in: ChatThread(mode: .auto), workspaceRoot: root)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await client.releaseFirstCall()

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

/// First call signals, then blocks until released, then throws invalidActionJSON — so the test can
/// cancel the owning task mid-call and prove the resolver honors the stop instead of re-prompting.
private actor BlockingThenThrowingLLMClientState {
    var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func enter() {
        calls += 1
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
    let onFirstCall: @Sendable () -> Void

    init(onFirstCall: @escaping @Sendable () -> Void) {
        self.onFirstCall = onFirstCall
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        await state.enter()
        let count = await state.calls
        if count == 1 {
            onFirstCall()
            await state.waitForRelease()
            throw TrustedRouterAgentError.invalidActionJSON("garbage-during-cancel")
        }
        return .say("should never be reached on a cancelled run")
    }

    func releaseFirstCall() async {
        await state.release()
    }

    func callCount() async -> Int {
        await state.calls
    }
}
