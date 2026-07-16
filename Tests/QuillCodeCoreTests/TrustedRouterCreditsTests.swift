import XCTest
@testable import QuillCodeCore

final class TrustedRouterCreditsTests: XCTestCase {
    func testSnapshotNormalizesCurrencyAndRejectsNonFiniteBalances() throws {
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 12.5,
            currency: " usd \n",
            fetchedAt: Date(timeIntervalSince1970: 100)
        ))

        XCTAssertEqual(snapshot.balance, 12.5)
        XCTAssertEqual(snapshot.currency, "USD")
        XCTAssertNil(TrustedRouterCreditsSnapshot(balance: .nan, currency: "USD"))
        XCTAssertNil(TrustedRouterCreditsSnapshot(balance: .infinity, currency: "USD"))
    }

    func testRefreshAndFailureTransitionsRetainLastKnownBalance() throws {
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 4.25,
            currency: "USD",
            fetchedAt: Date(timeIntervalSince1970: 100)
        ))
        let current = TrustedRouterCreditsState.current(snapshot)
        let refreshing = TrustedRouterCreditsState.refreshing(
            previous: current,
            attemptedAt: Date(timeIntervalSince1970: 120)
        )
        let stale = TrustedRouterCreditsState.failed(
            previous: refreshing,
            attemptedAt: Date(timeIntervalSince1970: 121),
            message: "network failed\nretry later"
        )

        XCTAssertEqual(refreshing.phase, .refreshing)
        XCTAssertEqual(refreshing.snapshot, snapshot)
        XCTAssertEqual(stale.phase, .stale)
        XCTAssertEqual(stale.snapshot, snapshot)
        XCTAssertEqual(stale.failureMessage, "network failed retry later")
    }

    func testFailureWithoutSnapshotIsFailedAndBoundsDiagnosticText() {
        let failure = TrustedRouterCreditsState.failed(
            previous: .unavailable,
            message: String(repeating: "x", count: 500)
        )

        XCTAssertEqual(failure.phase, .failed)
        XCTAssertNil(failure.snapshot)
        XCTAssertEqual(failure.failureMessage?.count, 240)
    }
}
