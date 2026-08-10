import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceTrustedRouterCreditsSurfaceBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testFormatsCurrentKeyUsageAndAllLimitWindows() throws {
        let snapshot = try makeSnapshot(
            lifetimeUsage: 86.090316,
            dailyUsage: 1.25,
            fetchedAt: now.addingTimeInterval(-90)
        )

        let surface = try XCTUnwrap(WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: .current(snapshot),
            hasCredential: true,
            now: now
        ).surface())

        XCTAssertEqual(surface.amountLabel, "Today $1.25 / $40.00")
        XCTAssertEqual(surface.compactLabel, "Today $1.25 / $40.00")
        XCTAssertEqual(surface.statusLabel, "Key limits current")
        XCTAssertEqual(surface.tone, .normal)
        XCTAssertEqual(surface.visibleLimits.map(\.periodLabel), ["Today", "Week", "Month", "Total"])
        XCTAssertEqual(surface.visibleLimits.map(\.usageLabel), [
            "$1.25 / $40.00",
            "$2.64 / $200.00",
            "$2.64 / $800.00",
            "$86.09 used"
        ])
        XCTAssertEqual(surface.visibleLimits.last?.remainingLabel, "No total cap")
        XCTAssertTrue(surface.detailLabel.contains("Updated 1m ago"))
        XCTAssertTrue(surface.accessibilityLabel.contains("$38.75 left"))
    }

    func testCurrentDetailIncludesBoundedKeyLimitHistory() throws {
        let older = try makeSnapshot(
            lifetimeUsage: 84,
            dailyUsage: 1,
            fetchedAt: now.addingTimeInterval(-3_600)
        )
        let current = try makeSnapshot(
            lifetimeUsage: 86,
            dailyUsage: 2,
            fetchedAt: now.addingTimeInterval(-90)
        )
        let state = TrustedRouterCreditsState.current(current, previous: .current(older))

        let surface = try XCTUnwrap(WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: state,
            hasCredential: true,
            now: now
        ).surface())

        XCTAssertEqual(
            surface.historyLabel,
            "Recent key-limit history: Today $2.00 / $40.00 updated 1m ago; Today $1.00 / $40.00 updated 1h ago."
        )
        XCTAssertTrue(surface.detailLabel.contains("Recent key-limit history"))
        XCTAssertTrue(surface.accessibilityLabel.contains("Week: $2.64 / $200.00"))
    }

    func testStaleSurfaceRoundsUsageAndRetainsFailureReason() throws {
        let snapshot = try makeSnapshot(
            lifetimeUsage: 0.0123,
            dailyUsage: 0.0123,
            currency: "EUR",
            fetchedAt: now.addingTimeInterval(-3_600)
        )
        let state = TrustedRouterCreditsState.failed(
            previous: .current(snapshot),
            attemptedAt: now,
            message: "Network unavailable."
        )

        let surface = try XCTUnwrap(WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: state,
            hasCredential: true,
            now: now
        ).surface())

        XCTAssertEqual(surface.amountLabel, "Today €0.01 / €40.00")
        XCTAssertEqual(surface.tone, .warning)
        XCTAssertTrue(surface.detailLabel.contains("Network unavailable."))
    }

    func testNearLimitUsesWarningTone() throws {
        let snapshot = try makeSnapshot(lifetimeUsage: 90, dailyUsage: 38)
        let surface = try XCTUnwrap(WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: .current(snapshot),
            hasCredential: true,
            now: now
        ).surface())

        XCTAssertEqual(surface.statusLabel, "Key limit nearly reached")
        XCTAssertEqual(surface.tone, .warning)
    }

    func testNoCredentialProducesNoAccountSurface() {
        XCTAssertNil(WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: .unavailable,
            hasCredential: false,
            now: now
        ).surface())
    }

    private func makeSnapshot(
        lifetimeUsage: Double,
        dailyUsage: Double,
        currency: String = "USD",
        fetchedAt: Date? = nil
    ) throws -> TrustedRouterCreditsSnapshot {
        try XCTUnwrap(TrustedRouterCreditsSnapshot(
            lifetime: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .lifetime, usage: lifetimeUsage)),
            daily: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(
                window: .daily,
                usage: dailyUsage,
                limit: 40,
                remaining: max(0, 40 - dailyUsage),
                resetsAt: now.addingTimeInterval(7_200)
            )),
            weekly: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(
                window: .weekly,
                usage: 2.643944,
                limit: 200,
                remaining: 197.356056,
                resetsAt: now.addingTimeInterval(2 * 86_400)
            )),
            monthly: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(
                window: .monthly,
                usage: 2.643944,
                limit: 800,
                remaining: 797.356056,
                resetsAt: now.addingTimeInterval(20 * 86_400)
            )),
            currency: currency,
            fetchedAt: fetchedAt ?? now
        ))
    }
}
