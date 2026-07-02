import XCTest
import QuillCodeCore
@testable import QuillCodeAgent

final class ContextOverflowDetectorTests: XCTestCase {
    private func httpError(_ statusCode: Int, body: String) -> TrustedRouterAgentError {
        .streamingHTTPError(statusCode: statusCode, body: body, rateLimit: nil)
    }

    // MARK: - Each signal normalizes to overflow

    func testHTTP413IsOverflowEvenWithOpaqueBody() {
        let signal = ContextOverflowDetector.signal(for: httpError(413, body: ""))
        XCTAssertEqual(signal, .httpPayloadTooLarge)
        XCTAssertTrue(ContextOverflowDetector.isContextOverflow(httpError(413, body: "anything")))
    }

    func testGatewayMachineCodeIsOverflow() {
        let body = #"{"error":{"code":"context_length_exceeded","message":"..."}}"#
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(400, body: body)), .machineCode)
    }

    func testTypeContextOverflowIsOverflow() {
        let body = #"{"error":{"type":"context_overflow"}}"#
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(422, body: body)), .machineCode)
    }

    func testContextWindowExceededCodeIsOverflow() {
        let body = #"{"code":"context_window_exceeded"}"#
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(400, body: body)), .machineCode)
    }

    func testProviderMessagePatternsAreOverflow() {
        let bodies = [
            "This model's maximum context length is 128000 tokens.",
            "Your prompt is too long. Please reduce the length of the messages.",
            "The input is too long for the requested model.",
            "This request exceeds the context window of the model.",
        ]
        for body in bodies {
            XCTAssertEqual(
                ContextOverflowDetector.signal(for: httpError(400, body: body)),
                .providerMessage,
                "expected overflow for body: \(body)"
            )
        }
    }

    func testMachineCodeMatchIsCaseInsensitive() {
        let body = #"{"CODE":"CONTEXT_LENGTH_EXCEEDED"}"#
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(400, body: body)), .machineCode)
    }

    // MARK: - Does NOT misfire on benign errors

    func testBenign413WithContextMarkerStaysOverflowButUnrelated400DoesNot() {
        // A plain 400 whose body merely mentions "tokens" (usage accounting) must NOT trip.
        let benign = "You have used 200 tokens on this request; billing updated."
        XCTAssertNil(ContextOverflowDetector.signal(for: httpError(400, body: benign)))
    }

    func testUnrelated429IsNotOverflow() {
        XCTAssertNil(ContextOverflowDetector.signal(for: httpError(429, body: "rate limit exceeded")))
    }

    func testUnrelated500IsNotOverflow() {
        XCTAssertNil(ContextOverflowDetector.signal(for: httpError(500, body: "internal server error")))
    }

    func testAuthErrorIsNotOverflow() {
        XCTAssertNil(ContextOverflowDetector.signal(for: httpError(401, body: "invalid api key")))
    }

    func testNonRouterErrorsAreNotOverflow() {
        XCTAssertNil(ContextOverflowDetector.signal(for: CancellationError()))
        XCTAssertNil(ContextOverflowDetector.signal(for: TrustedRouterAgentError.missingAPIKey))
        XCTAssertNil(ContextOverflowDetector.signal(for: TrustedRouterAgentError.emptyResponse))
        struct Other: Error {}
        XCTAssertNil(ContextOverflowDetector.signal(for: Other()))
    }

    // MARK: - Composition with RetryClassifier is non-destructive

    func testRetryClassifierBehaviorUnchangedForOverflowErrors() {
        // A 413/400 context overflow is a client error → RetryClassifier still says .none (do not
        // retry the identical prompt). The two systems are orthogonal.
        let overflow = httpError(413, body: "prompt is too long")
        XCTAssertEqual(RetryClassifier.classify(overflow), .none)
        XCTAssertTrue(ContextOverflowDetector.isContextOverflow(overflow))

        // A 429 is still rate-limited for the classifier and NOT overflow for the detector.
        let rateLimited = httpError(429, body: "slow down")
        XCTAssertEqual(RetryClassifier.classify(rateLimited), .rateLimited)
        XCTAssertFalse(ContextOverflowDetector.isContextOverflow(rateLimited))
    }

    // MARK: - Status gate: a rate-limit / transient status is NEVER overflow, even with a token body

    /// The MAJOR defect this guards: a persistent token-per-minute 429 whose body carries an
    /// Anthropic/OpenAI-style "too many tokens" / "reduce the length of the messages" message must NOT
    /// be reclassified as a context overflow (which would destructively compact the thread on what is
    /// really a rate limit). The status gate defers to RetryClassifier, so a 429 always stays a 429.
    func testRateLimit429WithTokenMentioningBodyIsNotOverflow() {
        let tokenBodies = [
            "Rate limit reached: too many tokens. Please reduce the length of the messages.",
            #"{"error":{"type":"rate_limit_error","message":"too many tokens, slow down"}}"#,
            "You have exceeded the context window of tokens-per-minute; retry after 60s.",
        ]
        for body in tokenBodies {
            XCTAssertNil(
                ContextOverflowDetector.signal(for: httpError(429, body: body)),
                "429 must never be overflow, even with body: \(body)"
            )
            XCTAssertFalse(ContextOverflowDetector.isContextOverflow(httpError(429, body: body)))
        }
    }

    func testTransient5xxWithTokenMentioningBodyIsNotOverflow() {
        // A 5xx server blip retries; even a misleading token-shaped body must not divert it to
        // compaction. Covers each transient 5xx the classifier retries.
        let body = "maximum context length exceeded; too many tokens in prompt"
        for status in [500, 502, 503, 504, 529] {
            XCTAssertNil(
                ContextOverflowDetector.signal(for: httpError(status, body: body)),
                "transient \(status) must never be overflow"
            )
        }
    }

    func testTimeout408WithTokenBodyIsNotOverflow() {
        XCTAssertNil(ContextOverflowDetector.signal(for: httpError(408, body: "too many tokens")))
    }

    func testDeterministicStatusesWithTokenBodyAreStillOverflow() {
        // The counterpart: 413/400/422 ARE deterministic client rejections, so the same token body
        // that must be ignored on a 429 correctly confirms overflow here.
        let body = "This model's maximum context length is 200000 tokens; reduce the length of the messages."
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(413, body: body)), .providerMessage)
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(400, body: body)), .providerMessage)
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(422, body: body)), .providerMessage)
    }

    func testOverflowEligibilityMatchesRetryClassifierTerminalStatuses() {
        // The gate is exactly "RetryClassifier says .none". Assert the boundary so a future change to
        // the classifier's transient set is caught here.
        XCTAssertTrue(ContextOverflowDetector.isOverflowEligible(statusCode: 400))
        XCTAssertTrue(ContextOverflowDetector.isOverflowEligible(statusCode: 413))
        XCTAssertTrue(ContextOverflowDetector.isOverflowEligible(statusCode: 422))
        XCTAssertFalse(ContextOverflowDetector.isOverflowEligible(statusCode: 429))
        XCTAssertFalse(ContextOverflowDetector.isOverflowEligible(statusCode: 408))
        XCTAssertFalse(ContextOverflowDetector.isOverflowEligible(statusCode: 500))
        XCTAssertFalse(ContextOverflowDetector.isOverflowEligible(statusCode: 529))
    }

    // MARK: - Proactive token threshold

    func testProactiveSignalTripsAtOrAboveLimit() {
        XCTAssertEqual(ContextOverflowDetector.proactiveSignal(estimatedTokens: 100, limit: 100), .tokenThreshold)
        XCTAssertEqual(ContextOverflowDetector.proactiveSignal(estimatedTokens: 101, limit: 100), .tokenThreshold)
    }

    func testProactiveSignalBelowLimitIsNil() {
        XCTAssertNil(ContextOverflowDetector.proactiveSignal(estimatedTokens: 99, limit: 100))
    }

    func testProactiveSignalWithNonPositiveLimitIsDisabled() {
        XCTAssertNil(ContextOverflowDetector.proactiveSignal(estimatedTokens: 1_000_000, limit: 0))
        XCTAssertNil(ContextOverflowDetector.proactiveSignal(estimatedTokens: 1_000_000, limit: -1))
    }

    // MARK: - Robustness on huge / empty bodies

    func testHugeBodyDoesNotTrapAndStillDetectsEarlyMarker() {
        let body = #"{"error":{"code":"context_length_exceeded"}}"# + String(repeating: "x", count: 2_000_000)
        XCTAssertEqual(ContextOverflowDetector.signal(for: httpError(400, body: body)), .machineCode)
    }

    func testHugeBodyWithNoMarkerIsNotOverflow() {
        let body = String(repeating: "x", count: 2_000_000)
        XCTAssertNil(ContextOverflowDetector.signal(for: httpError(400, body: body)))
    }

    func testEmptyBodyNon413IsNotOverflow() {
        XCTAssertNil(ContextOverflowDetector.signal(for: httpError(400, body: "")))
    }
}
