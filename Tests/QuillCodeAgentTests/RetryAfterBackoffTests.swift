import XCTest
import Foundation
@testable import QuillCodeAgent

// MARK: - Unit: the policy honoring a server-requested Retry-After

final class RetryAfterBackoffTests: XCTestCase {
    private let policy = RetryBackoffPolicy(
        maxAttempts: 6, base: .milliseconds(500), cap: .seconds(20), retryAfterCeiling: .seconds(60)
    )

    func testNilRetryAfterFallsThroughToBackoff() {
        let backoff = policy.delay(forAttempt: 3, jitter: 1.0)
        XCTAssertEqual(policy.delay(forAttempt: 3, jitter: 1.0, retryAfter: nil), backoff)
    }

    func testRetryAfterBelowBackoffKeepsBackoff() {
        // attempt 3, full jitter → min(20, 0.5*8)=4s backoff; a 1s server ask must not shorten it.
        XCTAssertEqual(policy.delay(forAttempt: 3, jitter: 1.0, retryAfter: .seconds(1)), .seconds(4))
    }

    func testRetryAfterAboveBackoffIsHonored() {
        // Zero jitter → zero backoff; the 10s server ask wins.
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 0.0, retryAfter: .seconds(10)), .seconds(10))
    }

    func testRetryAfterIsClampedToCeiling() {
        // A hostile Retry-After can't stall an unattended run past the ceiling.
        XCTAssertEqual(policy.delay(forAttempt: 0, jitter: 0.0, retryAfter: .seconds(999)), .seconds(60))
    }

    func testZeroRetryAfterFallsThroughToBackoff() {
        let backoff = policy.delay(forAttempt: 2, jitter: 1.0)
        XCTAssertEqual(policy.delay(forAttempt: 2, jitter: 1.0, retryAfter: .zero), backoff)
    }
}

// MARK: - Functional: the classifier extracting the server ask from an error

final class RetryAfterClassifierExtractionTests: XCTestCase {
    func testExtractsRetryAfterFromRateLimitedError() {
        let error = TrustedRouterAgentError.streamingHTTPError(
            statusCode: 429, body: "", rateLimit: HttpRateLimitDetails(retryAfter: .seconds(7))
        )
        XCTAssertEqual(RetryClassifier.retryAfter(error), .seconds(7))
    }

    func testErrorWithoutHintReturnsNil() {
        // The back-compat 2-arg shim carries no rate-limit details.
        let error = TrustedRouterAgentError.streamingHTTPError(statusCode: 429, body: "")
        XCTAssertNil(RetryClassifier.retryAfter(error))
    }

    func testNonRouterErrorReturnsNil() {
        XCTAssertNil(RetryClassifier.retryAfter(URLError(.timedOut)))
    }
}
