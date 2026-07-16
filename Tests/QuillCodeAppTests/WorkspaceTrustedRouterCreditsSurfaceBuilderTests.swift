import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceTrustedRouterCreditsSurfaceBuilderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testFormatsCurrentUSDAccountBalanceWithoutCallingItQuota() throws {
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 12.5,
            currency: "USD",
            fetchedAt: now.addingTimeInterval(-90)
        ))

        let surface = try XCTUnwrap(WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: .current(snapshot),
            hasCredential: true,
            now: now
        ).surface())

        XCTAssertEqual(surface.amountLabel, "$12.50")
        XCTAssertEqual(surface.compactLabel, "Balance $12.50")
        XCTAssertEqual(surface.statusLabel, "Balance current")
        XCTAssertEqual(surface.tone, .normal)
        XCTAssertTrue(surface.detailLabel.contains("Updated 1m ago"))
        XCTAssertFalse(surface.accessibilityLabel.localizedCaseInsensitiveContains("quota"))
    }

    func testStaleSurfaceRetainsPreciseSmallBalanceAndFailureReason() throws {
        let snapshot = try XCTUnwrap(TrustedRouterCreditsSnapshot(
            balance: 0.0123,
            currency: "EUR",
            fetchedAt: now.addingTimeInterval(-3_600)
        ))
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

        XCTAssertEqual(surface.amountLabel, "€0.0123")
        XCTAssertEqual(surface.tone, .warning)
        XCTAssertTrue(surface.detailLabel.contains("Network unavailable."))
    }

    func testNoCredentialProducesNoAccountSurface() {
        XCTAssertNil(WorkspaceTrustedRouterCreditsSurfaceBuilder(
            state: .unavailable,
            hasCredential: false,
            now: now
        ).surface())
    }
}
