import XCTest
@testable import QuillCodeAgent

final class HTTPRateLimitDetailsTests: XCTestCase {
    /// A fixed "now" so every date-form header parses deterministically.
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    private func iso(_ offset: TimeInterval) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
    }

    // MARK: - Retry-After

    func testRetryAfterDeltaSeconds() {
        let details = HTTPRateLimitDetails.parse(headers: ["Retry-After": "30"], now: now)
        XCTAssertEqual(details?.retryAfter, .seconds(30))
        XCTAssertEqual(details?.mandatedDelay, .seconds(30))
    }

    func testRetryAfterHTTPDate() throws {
        // "Wed, 21 Oct 2015 07:28:00 GMT" is epoch 1445412480; 90s after the injected now.
        let httpDateNow = Date(timeIntervalSince1970: 1_445_412_480 - 90)
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(
            headers: ["Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"],
            now: httpDateNow
        ))
        XCTAssertEqual(try XCTUnwrap(details.retryAfter).inSeconds, 90, accuracy: 1e-6)
    }

    func testRetryAfterDateInThePastClampsToZero() throws {
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(
            headers: ["Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"],
            now: Date(timeIntervalSince1970: 1_445_412_480 + 300)
        ))
        XCTAssertEqual(details.retryAfter, .seconds(0))
    }

    func testHeaderNamesMatchCaseInsensitively() {
        let details = HTTPRateLimitDetails.parse(
            headers: ["RETRY-AFTER": "12", "X-RateLimit-Remaining-Requests": "0"],
            now: now
        )
        XCTAssertEqual(details?.retryAfter, .seconds(12))
        XCTAssertEqual(details?.remaining, 0)
    }

    // MARK: - Anthropic-style headers

    func testAnthropicExhaustedQuotaWithRFC3339Reset() throws {
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "anthropic-ratelimit-requests-remaining": "0",
            "anthropic-ratelimit-requests-reset": iso(120),
        ], now: now))
        XCTAssertEqual(details.remaining, 0)
        XCTAssertEqual(try XCTUnwrap(details.resetAfter).inSeconds, 120, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(details.mandatedDelay).inSeconds, 120, accuracy: 1e-6)
    }

    func testAnthropicQuotaLeftIsNotAMandate() throws {
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "anthropic-ratelimit-tokens-remaining": "9000",
            "anthropic-ratelimit-tokens-reset": iso(60),
        ], now: now))
        XCTAssertEqual(details.remaining, 9000)
        XCTAssertNil(details.mandatedDelay)
    }

    func testExhaustedBucketPairsWithItsOwnReset() throws {
        // Tokens are exhausted (reset in 60s); requests are fine (reset in 1s). The mandate must be
        // the exhausted bucket's reset, not the soonest one.
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "anthropic-ratelimit-tokens-remaining": "0",
            "anthropic-ratelimit-tokens-reset": iso(60),
            "anthropic-ratelimit-requests-remaining": "500",
            "anthropic-ratelimit-requests-reset": iso(1),
        ], now: now))
        XCTAssertEqual(details.remaining, 0)
        XCTAssertEqual(try XCTUnwrap(details.mandatedDelay).inSeconds, 60, accuracy: 1e-6)
    }

    // MARK: - x-ratelimit-style headers

    func testXRateLimitExhaustedQuotaWithDeltaReset() {
        let details = HTTPRateLimitDetails.parse(headers: [
            "x-ratelimit-remaining-requests": "0",
            "x-ratelimit-reset-requests": "12",
        ], now: now)
        XCTAssertEqual(details?.remaining, 0)
        XCTAssertEqual(details?.mandatedDelay, .seconds(12))
    }

    func testXRateLimitResetSuffixedDurations() throws {
        let seconds = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "x-ratelimit-remaining": "0", "x-ratelimit-reset": "30s",
        ], now: now))
        XCTAssertEqual(try XCTUnwrap(seconds.resetAfter).inSeconds, 30, accuracy: 1e-6)
        let millis = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "x-ratelimit-remaining": "0", "x-ratelimit-reset": "250ms",
        ], now: now))
        XCTAssertEqual(try XCTUnwrap(millis.resetAfter).inSeconds, 0.25, accuracy: 1e-6)
    }

    func testOpenRouterStyleEpochMillisecondsReset() throws {
        // OpenRouter sends `X-RateLimit-Reset` as a unix epoch in MILLISECONDS (with that exact
        // casing). Locked in as a regression: it must land on the epoch-millis branch, not be read
        // as 1.75e12 delta-seconds.
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "X-RateLimit-Remaining": "0",
            "X-RateLimit-Reset": String((Int(now.timeIntervalSince1970) + 45) * 1000),
        ], now: now))
        XCTAssertEqual(details.remaining, 0)
        XCTAssertEqual(try XCTUnwrap(details.resetAfter).inSeconds, 45, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(details.mandatedDelay).inSeconds, 45, accuracy: 1e-6)
    }

    func testXRateLimitResetEpochForms() throws {
        // Epoch seconds (magnitude >= 1e9) and epoch milliseconds (>= 1e12), both 45s from now.
        let epochSeconds = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": String(Int(now.timeIntervalSince1970) + 45),
        ], now: now))
        XCTAssertEqual(try XCTUnwrap(epochSeconds.resetAfter).inSeconds, 45, accuracy: 1e-6)
        let epochMillis = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": String((Int(now.timeIntervalSince1970) + 45) * 1000),
        ], now: now))
        XCTAssertEqual(try XCTUnwrap(epochMillis.resetAfter).inSeconds, 45, accuracy: 1e-6)
    }

    // MARK: - Absence and garbage

    func testNoRecognizedHeadersParsesToNil() {
        XCTAssertNil(HTTPRateLimitDetails.parse(headers: [:], now: now))
        XCTAssertNil(HTTPRateLimitDetails.parse(headers: [
            "Content-Type": "application/json",
            "x-request-id": "abc123",
        ], now: now))
    }

    func testUnparseableValuesAreIgnored() {
        XCTAssertNil(HTTPRateLimitDetails.parse(headers: ["Retry-After": "soon"], now: now))
        let details = HTTPRateLimitDetails.parse(headers: [
            "Retry-After": "garbage",
            "x-ratelimit-remaining-requests": "0",
            "x-ratelimit-reset-requests": "not-a-number",
        ], now: now)
        XCTAssertEqual(details?.remaining, 0)
        XCTAssertNil(details?.resetAfter)
        XCTAssertNil(details?.mandatedDelay) // no usable reset -> no mandate
    }

    func testExhaustedBucketWithMissingResetDoesNotBorrowAHealthyBucketsReset() throws {
        // Tokens are exhausted but advertise NO reset; requests are healthy with a 1s reset. The
        // healthy bucket's informational reset must not be promoted into a mandate — the backoff
        // should fall back to plain exponential.
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "anthropic-ratelimit-tokens-remaining": "0",
            "anthropic-ratelimit-requests-remaining": "500",
            "anthropic-ratelimit-requests-reset": iso(1),
        ], now: now))
        XCTAssertEqual(details.remaining, 0)
        XCTAssertNil(details.resetAfter)
        XCTAssertNil(details.mandatedDelay)
    }

    // MARK: - Hostile values (Duration traps uncatchably on non-finite / astronomic seconds)

    /// The parser's clamp ceiling: 366 days, mirroring HTTPRateLimitDetails.maxDelaySeconds.
    private let clampCeiling: Double = 86_400 * 366

    func testRetryAfterNonFiniteValuesAreRejected() {
        // Double("inf")/Double("nan") parse successfully — they must be dropped, not trap.
        for hostile in ["inf", "-inf", "infinity", "Infinity", "nan", "NaN", "-nan", "1e400"] {
            XCTAssertNil(
                HTTPRateLimitDetails.parse(headers: ["Retry-After": hostile], now: now),
                "'\(hostile)' should be rejected outright"
            )
        }
    }

    func testRetryAfterFiniteHugeValuesAreClamped() throws {
        // Finite-huge still traps Duration (Int128 attoseconds overflow past ~1.7e20), so an
        // isFinite guard alone is insufficient. Double(String) also parses hex floats.
        for hostile in ["1e30", "2e20", "0x1p200", "999999999999999999999"] {
            let details = try XCTUnwrap(
                HTTPRateLimitDetails.parse(headers: ["Retry-After": hostile], now: now),
                "'\(hostile)'"
            )
            XCTAssertEqual(try XCTUnwrap(details.retryAfter).inSeconds, clampCeiling, accuracy: 1e-6, "'\(hostile)'")
        }
    }

    func testFarFutureRetryAfterDateIsClamped() throws {
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(
            headers: ["Retry-After": "Wed, 21 Oct 9999 07:28:00 GMT"],
            now: now
        ))
        XCTAssertEqual(try XCTUnwrap(details.retryAfter).inSeconds, clampCeiling, accuracy: 1e-6)
    }

    func testHugeEpochResetIsClampedNotTrapping() throws {
        let details = try XCTUnwrap(HTTPRateLimitDetails.parse(headers: [
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": "99999999999999999999",
        ], now: now))
        XCTAssertEqual(try XCTUnwrap(details.resetAfter).inSeconds, clampCeiling, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(details.mandatedDelay).inSeconds, clampCeiling, accuracy: 1e-6)
    }

    func testParseNeverTrapsOnArbitraryGarbage() {
        // Property-style sweep: every hostile value, in every recognized header slot, must degrade
        // to nil/clamped — and the downstream backoff arithmetic must not trap either.
        let hostileValues = [
            "inf", "-inf", "Infinity", "nan", "NaN", "-0", "-5", "+5",
            "1e30", "-1e30", "2e20", "1e308", "1e400", "0x1p200", "-0x1p200", "0x1.fp1000",
            "99999999999999999999", "999999999999999999999999ms", "1e19s", "infs", "nanms",
            "", " ", " 42 ", "garbage", "12e", "e12", "١٢٣", "🔥",
            "Wed, 21 Oct 9999 07:28:00 GMT", "9999-12-31T23:59:59Z", "10000-01-01T00:00:00Z",
        ]
        let policy = RetryBackoffPolicy()
        for hostile in hostileValues {
            for headers: [String: String] in [
                ["Retry-After": hostile],
                ["x-ratelimit-remaining": "0", "x-ratelimit-reset": hostile],
                ["x-ratelimit-remaining-requests": hostile, "x-ratelimit-reset-requests": hostile],
                ["anthropic-ratelimit-tokens-remaining": "0", "anthropic-ratelimit-tokens-reset": hostile],
                ["Retry-After": hostile, "x-ratelimit-remaining": hostile, "anthropic-ratelimit-requests-reset": hostile],
            ] {
                let details = HTTPRateLimitDetails.parse(headers: headers, now: now)
                // Exercise the full consumption path — mandate extraction and delay arithmetic.
                let delay = policy.delay(forAttempt: 3, jitter: 1.0, rateLimit: details)
                XCTAssertGreaterThanOrEqual(delay.inSeconds, 0, "'\(hostile)' in \(headers)")
                XCTAssertLessThanOrEqual(
                    delay.inSeconds,
                    max(policy.cap.inSeconds, policy.retryAfterCap.inSeconds),
                    "'\(hostile)' in \(headers)"
                )
            }
        }
    }
}
