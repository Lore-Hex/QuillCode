import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceTrustedRouterCreditsRefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)

    func testRequiresCredentialAndRefreshesUnavailableState() {
        let policy = WorkspaceTrustedRouterCreditsRefreshPolicy()

        XCTAssertFalse(policy.shouldRefresh(
            state: .unavailable,
            hasTrustedRouterAPIKey: false,
            now: now
        ))
        XCTAssertTrue(policy.shouldRefresh(
            state: .unavailable,
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    func testUsesFreshnessAndFailureBackoffWithoutOverlappingRefreshes() throws {
        let snapshot = try makeSnapshot(fetchedAt: now.addingTimeInterval(-59))
        let policy = WorkspaceTrustedRouterCreditsRefreshPolicy(
            staleAfter: 60,
            retryAfterFailure: 30
        )

        XCTAssertFalse(policy.shouldRefresh(
            state: .current(snapshot),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
        XCTAssertTrue(policy.shouldRefresh(
            state: .current(try makeSnapshot(fetchedAt: now.addingTimeInterval(-60))),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
        XCTAssertFalse(policy.shouldRefresh(
            state: .refreshing(previous: .current(snapshot), attemptedAt: now),
            hasTrustedRouterAPIKey: true,
            now: now
        ))

        let failed = TrustedRouterCreditsState.failed(
            previous: .unavailable,
            attemptedAt: now.addingTimeInterval(-29),
            message: "offline"
        )
        XCTAssertFalse(policy.shouldRefresh(state: failed, hasTrustedRouterAPIKey: true, now: now))
        XCTAssertTrue(policy.shouldRefresh(
            state: TrustedRouterCreditsState.failed(
                previous: .unavailable,
                attemptedAt: now.addingTimeInterval(-30),
                message: "offline"
            ),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    func testInvalidThresholdsDoNotDisableRefresh() throws {
        let snapshot = try makeSnapshot(fetchedAt: now)

        XCTAssertTrue(WorkspaceTrustedRouterCreditsRefreshPolicy(staleAfter: .nan).shouldRefresh(
            state: .current(snapshot),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    private func makeSnapshot(fetchedAt: Date) throws -> TrustedRouterCreditsSnapshot {
        try XCTUnwrap(TrustedRouterCreditsSnapshot(
            lifetime: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .lifetime, usage: 10)),
            daily: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .daily, usage: 1, limit: 40)),
            weekly: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .weekly, usage: 2, limit: 200)),
            monthly: XCTUnwrap(TrustedRouterCreditsWindowSnapshot(window: .monthly, usage: 3, limit: 800)),
            currency: "USD",
            fetchedAt: fetchedAt
        ))
    }
}
