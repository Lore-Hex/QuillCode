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

/// Shorthand for the streaming HTTP error — most tests here do not care about rate-limit headers.
private func httpError(_ statusCode: Int, body: String = "", rateLimit: HTTPRateLimitDetails? = nil) -> TrustedRouterAgentError {
    .streamingHTTPError(statusCode: statusCode, body: body, rateLimit: rateLimit)
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
        XCTAssertEqual(RetryClassifier.classify(httpError(429)), .rateLimited)
        for code in [500, 502, 503, 504, 408, 529] {
            XCTAssertEqual(RetryClassifier.classify(httpError(code)), .serverOverloaded, "\(code)")
        }
        for code in [400, 401, 403, 404, 422, 501, 505] {
            XCTAssertEqual(RetryClassifier.classify(httpError(code)), .none, "\(code)")
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

    // MARK: - Backoff with rate-limit guidance

    func testBackoffWithoutRateLimitGuidanceIsUnchanged() {
        let policy = RetryBackoffPolicy()
        for attempt in 0..<4 {
            for jitter in [0.0, 0.3, 1.0] {
                XCTAssertEqual(
                    policy.delay(forAttempt: attempt, jitter: jitter, rateLimit: nil),
                    policy.delay(forAttempt: attempt, jitter: jitter),
                    "attempt \(attempt) jitter \(jitter)"
                )
            }
        }
    }

    func testRetryAfterFloorsTheJitteredExponential() {
        let policy = RetryBackoffPolicy(base: .milliseconds(500), cap: .seconds(20))
        let guidance = HTTPRateLimitDetails(retryAfter: .seconds(5))
        // Exponential would be 0 (zero jitter) — the server's mandate wins.
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 0.0, rateLimit: guidance).inSeconds, 5.0, accuracy: 1e-9)
        // Exponential (0.5 * 2^5 = 16s) exceeds the 5s mandate — the exponential wins (a floor, not a ceiling).
        XCTAssertEqual(policy.delay(forAttempt: 5, jitter: 1.0, rateLimit: guidance).inSeconds, 16.0, accuracy: 1e-9)
    }

    func testRetryAfterIsCappedByRetryAfterCap() {
        let policy = RetryBackoffPolicy(retryAfterCap: .seconds(60))
        let hostile = HTTPRateLimitDetails(retryAfter: .seconds(3600))
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 0.0, rateLimit: hostile).inSeconds, 60.0, accuracy: 1e-9)
    }

    func testExhaustedQuotaResetActsAsMandateOnlyWhenRemainingIsZero() {
        let policy = RetryBackoffPolicy()
        // remaining == 0 with a reset time: authoritative — floors the delay.
        let exhausted = HTTPRateLimitDetails(remaining: 0, resetAfter: .seconds(12))
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 0.0, rateLimit: exhausted).inSeconds, 12.0, accuracy: 1e-9)
        // Quota left: the reset time is informational, not a mandate — plain exponential applies.
        let healthy = HTTPRateLimitDetails(remaining: 40, resetAfter: .seconds(12))
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 0.0, rateLimit: healthy).inSeconds, 0.0, accuracy: 1e-9)
    }

    func testExplicitRetryAfterTakesPrecedenceOverQuotaReset() {
        let policy = RetryBackoffPolicy()
        let guidance = HTTPRateLimitDetails(retryAfter: .seconds(7), remaining: 0, resetAfter: .seconds(30))
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 0.0, rateLimit: guidance).inSeconds, 7.0, accuracy: 1e-9)
    }

    // MARK: - Decorator behavior

    func testRetriesTransientThenSucceeds() async throws {
        let flaky = FlakyClient(failures: [
            httpError(429),
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
        let flaky = FlakyClient(failures: Array(repeating: httpError(503), count: 9))
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
        let flaky = FlakyClient(failures: [httpError(400, body: "bad")])
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

    func testDecoratorSleepsTheServerMandatedWaitOn429() async throws {
        // A 429 carrying Retry-After: 5 must sleep at least 5s even though the jittered
        // exponential (zero jitter here) would be 0 — the crux of honoring the header.
        let flaky = FlakyClient(failures: [
            httpError(429, rateLimit: HTTPRateLimitDetails(retryAfter: .seconds(5))),
        ])
        let sleeper = RecordingSleeper()
        let client = RetryingLLMClient(
            base: flaky,
            policy: RetryBackoffPolicy(),
            sleeper: sleeper,
            jitter: { 0.0 },
            onRetry: { _, _, _ in }
        )
        let action = try await client.nextAction(thread: thread, userMessage: "hi", tools: [])
        XCTAssertEqual(action, .say("ok"))
        XCTAssertEqual(sleeper.slept, [.seconds(5)])
    }

    func testStreamObtainIsRetried() async throws {
        // The production path: a 429 on obtaining the event stream is retried before any token.
        let flaky = FlakyClient(failures: [httpError(429)])
        let client = makeClient(flaky)
        let stream = try await client.actionEventStream(thread: thread, userMessage: "hi", tools: [])
        var events: [AgentTextStreamEvent] = []
        for try await event in stream { events.append(event) }
        XCTAssertEqual(events, [.text("ok")])
        XCTAssertEqual(flaky.callCount, 2)               // 1 failure + 1 success
    }
}
