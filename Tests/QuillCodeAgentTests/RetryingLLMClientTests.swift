import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

// MARK: - Test doubles

/// A UsageStreamingLLMClient whose obtain calls fail per a scripted queue then succeed, counting calls.
/// Sequential (the decorator awaits each attempt in turn), so plain mutable state is safe.
private final class FlakyClient: UsageStreamingLLMClient, @unchecked Sendable {
    var failures: [any Error]
    private(set) var callCount = 0

    init(failures: [any Error]) { self.failures = failures }

    private func nextOrThrow() throws {
        callCount += 1
        if !failures.isEmpty { throw failures.removeFirst() }
    }

    func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        try nextOrThrow()
        return .say("ok")
    }

    func actionTextStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<String, Error> {
        try nextOrThrow()
        return AsyncThrowingStream { continuation in continuation.yield("ok"); continuation.finish() }
    }

    func actionEventStream(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        try nextOrThrow()
        return AsyncThrowingStream { continuation in continuation.yield(.text("ok")); continuation.finish() }
    }
}

private final class RecordingSleeper: RetrySleeper, @unchecked Sendable {
    private(set) var slept: [Duration] = []
    func sleep(_ duration: Duration) async throws { slept.append(duration) }
}

private final class RetryRecorder: @unchecked Sendable {
    private(set) var events: [(attempt: Int, kind: TransientFailureClass)] = []
    func record(_ attempt: Int, _ kind: TransientFailureClass) { events.append((attempt, kind)) }
}

final class RetryingLLMClientTests: XCTestCase {
    private let thread = ChatThread(title: "t", messages: [], events: [])

    private func makeClient(
        _ flaky: FlakyClient,
        sleeper: RecordingSleeper = RecordingSleeper(),
        recorder: RetryRecorder = RetryRecorder(),
        policy: RetryBackoffPolicy = RetryBackoffPolicy()
    ) -> RetryingLLMClient<FlakyClient> {
        RetryingLLMClient(
            base: flaky,
            policy: policy,
            sleeper: sleeper,
            jitter: { 1.0 },
            onRetry: { attempt, kind, _ in recorder.record(attempt, kind) }
        )
    }

    // MARK: - Classifier

    func testClassifierTaxonomy() {
        XCTAssertEqual(RetryClassifier.classify(TrustedRouterAgentError.streamingHTTPError(statusCode: 429, body: "")), .rateLimited)
        for code in [500, 502, 503, 504, 408, 529] {
            XCTAssertEqual(RetryClassifier.classify(TrustedRouterAgentError.streamingHTTPError(statusCode: code, body: "")), .serverOverloaded, "\(code)")
        }
        for code in [400, 401, 403, 404, 422, 501, 505] {
            XCTAssertEqual(RetryClassifier.classify(TrustedRouterAgentError.streamingHTTPError(statusCode: code, body: "")), .none, "\(code)")
        }
        XCTAssertEqual(RetryClassifier.classify(TrustedRouterAgentError.emptyResponse), .transport)
        XCTAssertEqual(RetryClassifier.classify(TrustedRouterAgentError.missingAPIKey), .none)
        XCTAssertEqual(RetryClassifier.classify(TrustedRouterAgentError.invalidActionJSON("x")), .none)
        XCTAssertEqual(RetryClassifier.classify(URLError(.networkConnectionLost)), .transport)
        XCTAssertEqual(RetryClassifier.classify(URLError(.timedOut)), .transport)
        XCTAssertEqual(RetryClassifier.classify(URLError(.notConnectedToInternet)), .transport)
        XCTAssertEqual(RetryClassifier.classify(URLError(.badServerResponse)), .transport)
        XCTAssertEqual(RetryClassifier.classify(URLError(.badURL)), .none)
        // A TLS/cert failure is deterministic — must NOT be retried.
        XCTAssertEqual(RetryClassifier.classify(URLError(.secureConnectionFailed)), .none)
        // Raw POSIX socket faults surface as NSError and should still be treated as transport.
        XCTAssertEqual(RetryClassifier.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET))), .transport)
        XCTAssertEqual(RetryClassifier.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT))), .transport)
        // A non-network POSIX error (e.g. ENOENT) is not transient.
        XCTAssertEqual(RetryClassifier.classify(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))), .none)
        XCTAssertEqual(RetryClassifier.classify(CancellationError()), .none)
        XCTAssertEqual(RetryClassifier.classify(NSError(domain: "x", code: 1)), .none)
    }

    // MARK: - Backoff

    func testBackoffIsMonotonicCappedAndJittered() {
        let policy = RetryBackoffPolicy(maxAttempts: 6, base: .milliseconds(500), cap: .seconds(20))
        // Full jitter (1.0): 0.5, 1, 2, 4, 8, then capped at 20 (would be 16 -> under cap), then 20.
        let full = (0..<8).map { policy.delay(forAttempt: $0, jitter: 1.0).inSeconds }
        for i in 1..<full.count {
            XCTAssertGreaterThanOrEqual(full[i], full[i - 1], "should be monotonic at \(i)")
            XCTAssertLessThanOrEqual(full[i], 20.0 + 1e-9, "should be capped at \(i)")
        }
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 1.0).inSeconds, 0.5, accuracy: 1e-9)
        // Zero jitter collapses to zero delay.
        XCTAssertEqual(policy.delay(forAttempt: 3, jitter: 0.0).inSeconds, 0.0, accuracy: 1e-9)
        // Jitter scales the capped ceiling.
        XCTAssertEqual(policy.delay(forAttempt: 2, jitter: 0.5).inSeconds, 1.0, accuracy: 1e-9) // (0.5*4)=2, *0.5=1
    }

    // MARK: - Decorator behavior

    func testRetriesTransientThenSucceeds() async throws {
        let flaky = FlakyClient(failures: [
            TrustedRouterAgentError.streamingHTTPError(statusCode: 429, body: ""),
            URLError(.networkConnectionLost),
        ])
        let sleeper = RecordingSleeper()
        let recorder = RetryRecorder()
        let client = makeClient(flaky, sleeper: sleeper, recorder: recorder)

        let action = try await client.nextAction(thread: thread, userMessage: "hi", tools: [])
        XCTAssertEqual(action, .say("ok"))
        XCTAssertEqual(flaky.callCount, 3)               // 2 failures + 1 success
        XCTAssertEqual(sleeper.slept.count, 2)           // slept before each retry
        XCTAssertEqual(recorder.events.map(\.attempt), [1, 2])
        XCTAssertEqual(recorder.events.map(\.kind), [.rateLimited, .transport])
    }

    func testExhaustsAndRethrowsLastError() async {
        let flaky = FlakyClient(failures: Array(repeating: TrustedRouterAgentError.streamingHTTPError(statusCode: 503, body: ""), count: 9))
        let sleeper = RecordingSleeper()
        let client = makeClient(flaky, sleeper: sleeper, policy: RetryBackoffPolicy(maxAttempts: 4))
        do {
            _ = try await client.nextAction(thread: thread, userMessage: "hi", tools: [])
            XCTFail("should have thrown")
        } catch {
            XCTAssertEqual(RetryClassifier.classify(error), .serverOverloaded)
        }
        XCTAssertEqual(flaky.callCount, 4)               // maxAttempts total tries
        XCTAssertEqual(sleeper.slept.count, 3)           // one fewer sleep than attempts
    }

    func testNonTransientFailsFastWithoutRetry() async {
        let flaky = FlakyClient(failures: [TrustedRouterAgentError.streamingHTTPError(statusCode: 400, body: "bad")])
        let sleeper = RecordingSleeper()
        let client = makeClient(flaky, sleeper: sleeper)
        do {
            _ = try await client.nextAction(thread: thread, userMessage: "hi", tools: [])
            XCTFail("should have thrown")
        } catch {}
        XCTAssertEqual(flaky.callCount, 1)               // no retry on a 400
        XCTAssertTrue(sleeper.slept.isEmpty)
    }

    func testCancellationIsNeverRetried() async {
        let flaky = FlakyClient(failures: [CancellationError()])
        let sleeper = RecordingSleeper()
        let client = makeClient(flaky, sleeper: sleeper)
        do {
            _ = try await client.nextAction(thread: thread, userMessage: "hi", tools: [])
            XCTFail("should have thrown")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(flaky.callCount, 1)
        XCTAssertTrue(sleeper.slept.isEmpty)
    }

    // MARK: - Retry-After honoring (integration through withRetry)

    func testServerRetryAfterIsHonoredOverBackoff() async throws {
        // A 429 that asks for 5s; jitter collapses our own backoff to ~0, so the ONLY reason the
        // decorator would sleep 5s is that it honored the server's Retry-After end-to-end.
        let flaky = FlakyClient(failures: [
            TrustedRouterAgentError.streamingHTTPError(
                statusCode: 429, body: "", rateLimit: HttpRateLimitDetails(retryAfter: .seconds(5))
            ),
        ])
        let sleeper = RecordingSleeper()
        let client = RetryingLLMClient(
            base: flaky, policy: RetryBackoffPolicy(), sleeper: sleeper, jitter: { 0.0 }, onRetry: { _, _, _ in }
        )

        let action = try await client.nextAction(thread: thread, userMessage: "hi", tools: [])
        XCTAssertEqual(action, .say("ok"))
        XCTAssertEqual(flaky.callCount, 2)
        XCTAssertEqual(sleeper.slept, [.seconds(5)])
    }

    func testOurBackoffWinsWhenLongerThanRetryAfter() async throws {
        // A tiny Retry-After must never make us LESS patient than our own jittered backoff (0.5s here).
        let flaky = FlakyClient(failures: [
            TrustedRouterAgentError.streamingHTTPError(
                statusCode: 429, body: "", rateLimit: HttpRateLimitDetails(retryAfter: .milliseconds(100))
            ),
        ])
        let sleeper = RecordingSleeper()
        let client = RetryingLLMClient(
            base: flaky, policy: RetryBackoffPolicy(base: .milliseconds(500)), sleeper: sleeper,
            jitter: { 1.0 }, onRetry: { _, _, _ in }
        )

        _ = try await client.nextAction(thread: thread, userMessage: "hi", tools: [])
        XCTAssertEqual(sleeper.slept, [.milliseconds(500)])
    }

    func testStreamObtainIsRetried() async throws {
        // The production path: a 429 on obtaining the event stream is retried before any token.
        let flaky = FlakyClient(failures: [TrustedRouterAgentError.streamingHTTPError(statusCode: 429, body: "")])
        let client = makeClient(flaky)
        let stream = try await client.actionEventStream(thread: thread, userMessage: "hi", tools: [])
        var events: [AgentTextStreamEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events, [.text("ok")])
        XCTAssertEqual(flaky.callCount, 2)               // 1 failure + 1 success
    }
}
