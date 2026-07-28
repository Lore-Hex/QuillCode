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
        XCTAssertEqual(refreshing.history, [snapshot])
        XCTAssertEqual(stale.phase, .stale)
        XCTAssertEqual(stale.snapshot, snapshot)
        XCTAssertEqual(stale.history, [snapshot])
        XCTAssertEqual(stale.failureMessage, "network failed retry later")
    }

    func testSuccessfulRefreshHistoryIsMostRecentFirstDeduplicatedAndBounded() throws {
        let snapshots = try (0..<30).map { index in
            try XCTUnwrap(TrustedRouterCreditsSnapshot(
                balance: Double(index),
                currency: "USD",
                fetchedAt: Date(timeIntervalSince1970: Double(index))
            ))
        }

        let state = snapshots.reduce(TrustedRouterCreditsState.unavailable) { previous, snapshot in
            TrustedRouterCreditsState.current(snapshot, previous: previous)
        }
        let repeated = TrustedRouterCreditsState.current(snapshots[29], previous: state)

        XCTAssertEqual(state.history.count, TrustedRouterCreditsState.maxHistoryCount)
        XCTAssertEqual(state.history.first, snapshots[29])
        XCTAssertEqual(state.history.last, snapshots[6])
        XCTAssertEqual(repeated.history, state.history)
    }

    func testDecodesOlderStateWithoutHistoryAndSeedsSnapshotAsHistory() throws {
        let json = """
        {
          "phase": "current",
          "snapshot": {
            "balance": 4.25,
            "currency": "USD",
            "fetchedAt": 100
          },
          "lastAttemptAt": 100
        }
        """

        let state = try JSONDecoder().decode(
            TrustedRouterCreditsState.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(state.phase, .current)
        XCTAssertEqual(state.snapshot?.balance, 4.25)
        XCTAssertEqual(state.history, [state.snapshot].compactMap { $0 })
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
