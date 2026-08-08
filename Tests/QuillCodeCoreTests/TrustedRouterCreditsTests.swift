import XCTest
@testable import QuillCodeCore

final class TrustedRouterCreditsTests: XCTestCase {
    func testSnapshotNormalizesCurrencyAndExposesOrderedWindows() throws {
        let snapshot = try makeSnapshot(
            lifetimeUsage: 12.5,
            dailyUsage: 1.25,
            dailyLimit: 10,
            currency: " usd \n",
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(snapshot.lifetime.usage, 12.5)
        XCTAssertEqual(snapshot.daily.remaining, 8.75)
        XCTAssertEqual(snapshot.daily.usedPercent, 13)
        XCTAssertEqual(snapshot.currency, "USD")
        XCTAssertEqual(snapshot.windows.map(\.window), [.daily, .weekly, .monthly, .lifetime])
        XCTAssertEqual(snapshot.primaryWindow, snapshot.daily)
    }

    func testWindowRejectsInvalidMoneyValuesAndSnapshotRejectsMismatchedWindows() throws {
        XCTAssertNil(TrustedRouterCreditsWindowSnapshot(window: .daily, usage: .nan))
        XCTAssertNil(TrustedRouterCreditsWindowSnapshot(window: .daily, usage: .infinity))
        XCTAssertNil(TrustedRouterCreditsWindowSnapshot(window: .daily, usage: -1))
        XCTAssertNil(TrustedRouterCreditsWindowSnapshot(window: .daily, usage: 1, limit: -1))

        let daily = try XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .daily, usage: 1))
        XCTAssertNil(TrustedRouterCreditsSnapshot(
            lifetime: daily,
            daily: daily,
            weekly: try XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .weekly, usage: 0)),
            monthly: try XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .monthly, usage: 0)),
            currency: "USD"
        ))
    }

    func testRefreshAndFailureTransitionsRetainLastKnownUsage() throws {
        let snapshot = try makeSnapshot(lifetimeUsage: 4.25, fetchedAt: Date(timeIntervalSince1970: 100))
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
            try makeSnapshot(
                lifetimeUsage: Double(index),
                fetchedAt: Date(timeIntervalSince1970: Double(index))
            )
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

    func testDecodesStateWithoutHistoryAndSeedsSnapshotAsHistory() throws {
        let snapshot = try makeSnapshot(lifetimeUsage: 4.25, fetchedAt: Date(timeIntervalSince1970: 100))
        let encoded = try JSONEncoder().encode(TrustedRouterCreditsState.current(snapshot))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "history")

        let state = try JSONDecoder().decode(
            TrustedRouterCreditsState.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(state.phase, .current)
        XCTAssertEqual(state.snapshot?.lifetime.usage, 4.25)
        XCTAssertEqual(state.history, [snapshot])
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

    private func makeSnapshot(
        lifetimeUsage: Double,
        dailyUsage: Double = 0,
        dailyLimit: Double? = 40,
        currency: String = "USD",
        fetchedAt: Date = Date()
    ) throws -> TrustedRouterCreditsSnapshot {
        try XCTUnwrap(TrustedRouterCreditsSnapshot(
            lifetime: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .lifetime, usage: lifetimeUsage)),
            daily: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(
                window: .daily,
                usage: dailyUsage,
                limit: dailyLimit
            )),
            weekly: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .weekly, usage: 0, limit: 200)),
            monthly: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .monthly, usage: 0, limit: 800)),
            currency: currency,
            fetchedAt: fetchedAt
        ))
    }
}
