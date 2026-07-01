import XCTest
import Foundation
@testable import QuillCodeAgent

// MARK: - Unit: the pure header parser

final class HttpRateLimitDetailsTests: XCTestCase {
    // A fixed reference instant: 2023-11-14 22:13:20 GMT.
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func retryAfter(_ headers: [String: String]) -> Duration? {
        HttpRateLimitDetails.parse(headers: headers, now: now).retryAfter
    }

    func testRetryAfterIntegerSeconds() {
        XCTAssertEqual(retryAfter(["Retry-After": "12"]), .seconds(12))
    }

    func testRetryAfterDecimalSeconds() {
        XCTAssertEqual(retryAfter(["retry-after": "2.5"]), .milliseconds(2500))
    }

    func testRetryAfterHttpDate() {
        // 30 seconds after `now`.
        XCTAssertEqual(retryAfter(["Retry-After": "Tue, 14 Nov 2023 22:13:50 GMT"]), .seconds(30))
    }

    func testRetryAfterIso8601Date() {
        XCTAssertEqual(retryAfter(["retry-after": "2023-11-14T22:13:50Z"]), .seconds(30))
    }

    func testPastResetClampsToZeroNotNegative() {
        // 10 seconds BEFORE now — "retry now", never a negative delay.
        XCTAssertEqual(retryAfter(["Retry-After": "Tue, 14 Nov 2023 22:13:10 GMT"]), .zero)
    }

    func testHeaderKeysAreCaseInsensitive() {
        XCTAssertEqual(retryAfter(["RETRY-AFTER": "5"]), .seconds(5))
    }

    func testRatelimitResetUnixEpochIsTreatedAsAbsolute() {
        // A big number in a reset field is an absolute unix timestamp, not a 1.7-billion-second delay.
        XCTAssertEqual(retryAfter(["x-ratelimit-reset": "1700000045"]), .seconds(45))
    }

    func testNonFiniteRetryAfterIsIgnoredNotCrash() {
        // Double("inf") parses to +inf, which would trap Duration.seconds — a malformed/hostile header
        // must degrade to "no hint", never crash the process.
        for value in ["inf", "Infinity", "-inf", "nan", "1e400"] {
            XCTAssertNil(retryAfter(["Retry-After": value]), "\(value) must be ignored, not crash")
            XCTAssertNil(retryAfter(["x-ratelimit-reset": value]), "\(value) (reset) must be ignored")
        }
    }

    func testRetryAfterLargeNumberIsDelaySecondsNotEpoch() {
        // Per RFC 7231, Retry-After is delay-seconds or HTTP-date — never an absolute epoch. A large
        // value must stay a (large) delay, NOT be misread as a past timestamp and collapsed to zero.
        XCTAssertEqual(retryAfter(["Retry-After": "1700000045"]), .seconds(1_700_000_045))
    }

    func testAnthropicUnifiedResetIso8601() {
        XCTAssertEqual(retryAfter(["anthropic-ratelimit-unified-reset": "2023-11-14T22:14:20Z"]), .seconds(60))
    }

    func testGoDurationResetHeader() {
        XCTAssertEqual(retryAfter(["x-ratelimit-reset-requests": "6m0s"]), .seconds(360))
        XCTAssertEqual(retryAfter(["x-ratelimit-reset-tokens": "1m30s"]), .seconds(90))
    }

    func testRetryAfterTakesPrecedenceOverResetHeaders() {
        let d = retryAfter(["Retry-After": "3", "x-ratelimit-reset": "1700009999"])
        XCTAssertEqual(d, .seconds(3))
    }

    func testNoRateLimitHeadersIsEmpty() {
        XCTAssertTrue(HttpRateLimitDetails.parse(headers: ["content-type": "text/plain"], now: now).isEmpty)
    }

    func testMalformedValueIsIgnored() {
        XCTAssertNil(retryAfter(["Retry-After": "soon"]))
    }

    func testGoDurationSubSecond() {
        XCTAssertEqual(HttpRateLimitDetails.parseGoDuration("500ms"), 0.5)
        XCTAssertEqual(HttpRateLimitDetails.parseGoDuration("1.5s"), 1.5)
        XCTAssertEqual(HttpRateLimitDetails.parseGoDuration("100µs") ?? -1, 0.0001, accuracy: 1e-12)
        XCTAssertNil(HttpRateLimitDetails.parseGoDuration("garbage"))
        XCTAssertNil(HttpRateLimitDetails.parseGoDuration("10"))   // no unit
    }

    // MARK: - Functional: through a real HTTPURLResponse

    func testParsesFromHttpUrlResponse() {
        let response = HTTPURLResponse(
            url: URL(string: "https://api.trustedrouter.com/chat/completions")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "7"]
        )!
        XCTAssertEqual(HttpRateLimitDetails.parse(response: response, now: now).retryAfter, .seconds(7))
    }
}
