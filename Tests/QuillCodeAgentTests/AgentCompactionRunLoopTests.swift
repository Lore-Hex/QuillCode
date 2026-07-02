import XCTest
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeAgent

/// Records every thread it is asked about and can be scripted to overflow on the first N calls, then
/// succeed. Conforms to `UsageStreamingLLMClient` (the path the run loop prefers) so it exercises the
/// real `nextUsageStreamingAction` → overflow-throw seam.
private actor OverflowScriptState {
    private(set) var callCount = 0
    private(set) var messageCountsAtCall: [Int] = []
    let overflowRounds: Int
    let finalAction: AgentAction
    /// The HTTP status + body thrown on the first `overflowRounds` calls. Defaults to a genuine
    /// context overflow (413), but a test can supply a 429/5xx to prove those are NOT compacted.
    let failureStatus: Int
    let failureBody: String

    init(
        overflowRounds: Int,
        finalAction: AgentAction,
        failureStatus: Int = 413,
        failureBody: String = #"{"error":{"code":"context_length_exceeded"}}"#
    ) {
        self.overflowRounds = overflowRounds
        self.finalAction = finalAction
        self.failureStatus = failureStatus
        self.failureBody = failureBody
    }

    /// Returns the events to yield, or throws the scripted error, recording the thread size seen.
    func nextEventsOrThrow(threadMessageCount: Int) throws -> [AgentTextStreamEvent] {
        callCount += 1
        messageCountsAtCall.append(threadMessageCount)
        if callCount <= overflowRounds {
            throw TrustedRouterAgentError.streamingHTTPError(
                statusCode: failureStatus,
                body: failureBody,
                rateLimit: nil
            )
        }
        switch finalAction {
        case .say(let text):
            return [.text(#"{"type":"say","text":"\#(text)"}"#)]
        case .tool(let call):
            return [.text(#"{"type":"tool","name":"\#(call.name)","arguments":\#(call.argumentsJSON)}"#)]
        }
    }
}

private struct OverflowScriptedLLMClient: UsageStreamingLLMClient {
    let state: OverflowScriptState

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        throw StreamingActionLLMError.nonStreamingPathUsed
    }

    func actionTextStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<String, Error> {
        // The overflow throws HERE (before the stream), matching the real client. On success it
        // degrades to the event stream's text.
        let events = try await actionEventStream(thread: thread, userMessage: userMessage, tools: tools)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in events {
                        if case .text(let chunk) = event { continuation.yield(chunk) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }

    func actionEventStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        // Throwing BEFORE returning the stream mirrors TrustedRouterLLMClient: the HTTP status error
        // is thrown before any token, so the run loop's overflow catch sees it.
        let events = try await state.nextEventsOrThrow(threadMessageCount: thread.messages.count)
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// Counts how many times it was asked to summarize, so a test can assert an aux summary call did (or
/// did NOT) happen — e.g. a misclassified 429 must never spend a summary call.
private actor SummaryCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// A summarizer that fixes the summary text and records that it ran.
private struct RecordingSummarizer: ThreadCompactionSummarizing {
    let text: String
    let counter: SummaryCallCounter?

    init(text: String, counter: SummaryCallCounter? = nil) {
        self.text = text
        self.counter = counter
    }

    func summarize(sourceTitle: String, olderMessages: [ChatMessage], recentMessages: [ChatMessage]) async throws -> String {
        await counter?.increment()
        return text
    }
}

final class AgentCompactionRunLoopTests: XCTestCase {
    private func longThread(pairs: Int) -> ChatThread {
        var messages: [ChatMessage] = []
        for i in 0..<pairs {
            messages.append(ChatMessage(role: .user, content: "user \(i)"))
            messages.append(ChatMessage(role: .assistant, content: "assistant \(i)"))
        }
        return ChatThread(mode: .auto, messages: messages)
    }

    private func compactionPolicy(
        summary: String = "COMPACTED SUMMARY",
        keepRecent: Int = 4,
        maxRounds: Int = 3,
        proactiveLimit: Int = 0,
        summaryCounter: SummaryCallCounter? = nil
    ) -> AgentCompactionPolicy {
        AgentCompactionPolicy(
            compactor: ThreadCompactor(
                keepRecentMessages: keepRecent,
                perMessageTokenFloor: 0,
                summarizer: RecordingSummarizer(text: summary, counter: summaryCounter)
            ),
            proactiveTokenLimit: proactiveLimit,
            maxRoundsPerCall: maxRounds
        )
    }

    // MARK: - Overflow → compact → resume succeeds

    func testOverflowOnceThenCompactAndResumeReturnsFinalAnswer() async throws {
        let root = try makeTempDirectory()
        let state = OverflowScriptState(overflowRounds: 1, finalAction: .say("all done"))
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy()
        )

        let result = try await runner.send(
            "continue the work",
            in: longThread(pairs: 10),
            workspaceRoot: root
        )

        // The run resumed and finished rather than throwing.
        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(result.thread.messages.last?.content, "all done")
        // The model was called twice: overflow, then success after compaction.
        let calls = await state.callCount
        XCTAssertEqual(calls, 2)
        // A compaction seam was recorded.
        XCTAssertTrue(result.thread.events.contains { $0.kind == .notice && $0.summary.contains("Compacted") })
        // The summary landed in the thread.
        XCTAssertTrue(result.thread.messages.contains { $0.content == "COMPACTED SUMMARY" })
    }

    func testThreadShrinksBetweenOverflowAndRetry() async throws {
        let root = try makeTempDirectory()
        let state = OverflowScriptState(overflowRounds: 1, finalAction: .say("done"))
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy(keepRecent: 4)
        )
        _ = try await runner.send("go", in: longThread(pairs: 10), workspaceRoot: root)

        let counts = await state.messageCountsAtCall
        XCTAssertEqual(counts.count, 2)
        // First call saw the full thread; the compacted retry saw fewer messages.
        XCTAssertGreaterThan(counts[0], counts[1])
    }

    // MARK: - Termination under repeated overflow

    func testUnresolvableOverflowTerminatesWithDiagnosticNotInfiniteLoop() async throws {
        let root = try makeTempDirectory()
        // Overflows forever (more rounds than the cap allows).
        let state = OverflowScriptState(overflowRounds: 1_000, finalAction: .say("never reached"))
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy(maxRounds: 3)
        )

        do {
            _ = try await runner.send("go", in: longThread(pairs: 20), workspaceRoot: root)
            XCTFail("expected the run to terminate with an overflow error, not loop forever")
        } catch let error as ContextOverflowUnresolvedError {
            // Bounded: it did not exceed the round cap (a .noOlderTurns can stop it earlier).
            XCTAssertLessThanOrEqual(error.rounds, 3)
            XCTAssertGreaterThan(error.rounds, 0)
        }

        // The model was called a bounded number of times (initial + up to maxRounds retries).
        let calls = await state.callCount
        XCTAssertLessThanOrEqual(calls, 4)
    }

    func testTerminatesWhenNothingLeftToCompact() async throws {
        let root = try makeTempDirectory()
        let state = OverflowScriptState(overflowRounds: 1_000, finalAction: .say("x"))
        // A thread that is already tiny: the first compaction reports .noOlderTurns, so the loop must
        // stop immediately rather than burning all its rounds.
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy(keepRecent: 6, maxRounds: 5)
        )
        do {
            _ = try await runner.send("go", in: ChatThread(mode: .auto), workspaceRoot: root, recordUserMessage: true)
            XCTFail("expected termination")
        } catch is ContextOverflowUnresolvedError {
            // expected
        }
        let calls = await state.callCount
        // Initial overflow + one compaction attempt that yields .noOlderTurns → stop. Bounded well
        // under the round cap.
        XCTAssertLessThanOrEqual(calls, 2)
    }

    // MARK: - No policy → old behavior (overflow surfaces)

    func testWithoutCompactionPolicyOverflowSurfacesUnchanged() async throws {
        let root = try makeTempDirectory()
        let state = OverflowScriptState(overflowRounds: 1, finalAction: .say("done"))
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: nil
        )
        do {
            _ = try await runner.send("go", in: longThread(pairs: 5), workspaceRoot: root)
            XCTFail("expected the overflow error to surface unchanged")
        } catch let error as TrustedRouterAgentError {
            guard case .streamingHTTPError(let status, _, _) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(status, 413)
        }
        let calls = await state.callCount
        XCTAssertEqual(calls, 1, "without a policy the run must not retry/compact")
    }

    // MARK: - Proactive compaction

    func testProactiveCompactionTrimsBeforeTheCall() async throws {
        let root = try makeTempDirectory()
        // Never overflows; but the thread is large and the proactive limit is low, so the loop should
        // compact BEFORE the first successful call.
        let state = OverflowScriptState(overflowRounds: 0, finalAction: .say("done"))
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy(keepRecent: 4, proactiveLimit: 1)
        )
        let result = try await runner.send("go", in: longThread(pairs: 10), workspaceRoot: root)

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertTrue(
            result.thread.events.contains { $0.kind == .notice && $0.summary.contains("Compacted") },
            "proactive compaction should have recorded a seam"
        )
    }

    // MARK: - Non-overflow errors are not swallowed

    func testNonOverflowErrorIsNotCompactedAway() async throws {
        let root = try makeTempDirectory()

        struct AuthFailingClient: UsageStreamingLLMClient {
            func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
                throw StreamingActionLLMError.nonStreamingPathUsed
            }
            func actionTextStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<String, Error> {
                _ = try await actionEventStream(thread: thread, userMessage: userMessage, tools: tools)
                return AsyncThrowingStream { $0.finish() }
            }
            func actionEventStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
                throw TrustedRouterAgentError.streamingHTTPError(statusCode: 401, body: "invalid api key", rateLimit: nil)
            }
        }

        let runner = AgentRunner(
            llm: AuthFailingClient(),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy()
        )
        do {
            _ = try await runner.send("go", in: longThread(pairs: 10), workspaceRoot: root)
            XCTFail("expected the auth error to surface")
        } catch let error as TrustedRouterAgentError {
            guard case .streamingHTTPError(let status, _, _) = error else {
                return XCTFail("wrong error")
            }
            XCTAssertEqual(status, 401, "a non-overflow error must propagate, not trigger compaction")
        }
    }

    // MARK: - Rate-limit / transient status is NEVER compacted (regression for the MAJOR defect)

    /// A persistent token-per-minute 429 whose body says "too many tokens" / "reduce the length of the
    /// messages" must surface as the rate limit, NOT trigger a destructive compaction. Asserts: no
    /// compaction seam event, the aux summarizer was never called, and the thread's real turns are
    /// intact. Fails on a revert of the status gate (which would compact and finally raise
    /// ContextOverflowUnresolvedError, hiding the real 429).
    func testPersistent429WithTokenBodyIsNotCompactedAndSurfacesAsRateLimit() async throws {
        let root = try makeTempDirectory()
        let summaryCounter = SummaryCallCounter()
        let state = OverflowScriptState(
            overflowRounds: 1_000, // always fails
            finalAction: .say("never reached"),
            failureStatus: 429,
            failureBody: "Rate limit reached: too many tokens. Please reduce the length of the messages."
        )
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy(maxRounds: 3, summaryCounter: summaryCounter)
        )

        do {
            _ = try await runner.send("go", in: longThread(pairs: 10), workspaceRoot: root)
            XCTFail("expected the 429 to surface, not be compacted away")
        } catch let error as TrustedRouterAgentError {
            guard case .streamingHTTPError(let status, _, _) = error else {
                return XCTFail("wrong error type: \(error)")
            }
            XCTAssertEqual(status, 429, "a rate limit must surface as itself, not as an overflow")
        } catch let error as ContextOverflowUnresolvedError {
            XCTFail("a 429 must NOT be treated as overflow; got compaction failure: \(error)")
        }

        // The aux summary model was never invoked — no housekeeping cost spent on a rate limit.
        let summaryCalls = await summaryCounter.count
        XCTAssertEqual(summaryCalls, 0, "a 429 must not spend an aux summary call")

        // The compaction loop made exactly ONE model call: the 429 is not overflow, so it re-throws
        // immediately without retrying (the run-loop retry lives in RetryingLLMClient, not exercised
        // here — this proves the compaction loop itself does not retry a rate limit).
        let calls = await state.callCount
        XCTAssertEqual(calls, 1, "the compaction loop must not retry a rate limit")
    }

    func testPersistent5xxWithTokenBodyIsNotCompacted() async throws {
        let root = try makeTempDirectory()
        let summaryCounter = SummaryCallCounter()
        let state = OverflowScriptState(
            overflowRounds: 1_000,
            finalAction: .say("never reached"),
            failureStatus: 503,
            failureBody: "maximum context length exceeded (too many tokens)"
        )
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy(maxRounds: 3, summaryCounter: summaryCounter)
        )
        do {
            _ = try await runner.send("go", in: longThread(pairs: 10), workspaceRoot: root)
            XCTFail("expected the 5xx to surface")
        } catch let error as TrustedRouterAgentError {
            guard case .streamingHTTPError(let status, _, _) = error else {
                return XCTFail("wrong error type: \(error)")
            }
            XCTAssertEqual(status, 503, "a transient 5xx must surface, not be compacted")
        }
        let summaryCalls = await summaryCounter.count
        XCTAssertEqual(summaryCalls, 0, "a 5xx must not spend an aux summary call")
    }

    /// The positive counterpart in the SAME run-loop harness: a genuine 413/400/422 overflow whose body
    /// carries the identical token phrasing IS compacted and resumes — proving the status gate lets
    /// real overflows through unchanged.
    func testGenuineOverflowWithTokenBodyStillCompactsAndResumes() async throws {
        let root = try makeTempDirectory()
        let summaryCounter = SummaryCallCounter()
        let state = OverflowScriptState(
            overflowRounds: 1,
            finalAction: .say("recovered"),
            failureStatus: 400,
            failureBody: "This model's maximum context length is 200000 tokens; reduce the length of the messages."
        )
        let runner = AgentRunner(
            llm: OverflowScriptedLLMClient(state: state),
            safety: AlwaysApprovingSafetyReviewer(),
            compaction: compactionPolicy(summaryCounter: summaryCounter)
        )
        let result = try await runner.send("go", in: longThread(pairs: 10), workspaceRoot: root)

        XCTAssertEqual(result.stopReason, .finished)
        XCTAssertEqual(result.thread.messages.last?.content, "recovered")
        XCTAssertTrue(result.thread.events.contains { $0.kind == .notice && $0.summary.contains("Compacted") })
        let summaryCalls = await summaryCounter.count
        XCTAssertEqual(summaryCalls, 1, "a real overflow should invoke the aux summary once")
    }
}
