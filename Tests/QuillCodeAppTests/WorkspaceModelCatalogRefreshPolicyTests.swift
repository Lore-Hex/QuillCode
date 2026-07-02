import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceModelCatalogRefreshPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000)

    func testDoesNotRefreshWithoutTrustedRouterKey() {
        let policy = WorkspaceModelCatalogRefreshPolicy()

        XCTAssertFalse(policy.shouldRefresh(
            status: .bundled,
            hasTrustedRouterAPIKey: false,
            now: now
        ))
        XCTAssertFalse(policy.shouldRefresh(
            status: .liveTrustedRouter(fetchedAt: now.addingTimeInterval(-7_200)),
            hasTrustedRouterAPIKey: false,
            now: now
        ))
    }

    func testRefreshesBundledCatalogWhenTrustedRouterKeyExists() {
        let policy = WorkspaceModelCatalogRefreshPolicy()

        XCTAssertTrue(policy.shouldRefresh(
            status: .bundled,
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    func testRefreshesLiveCatalogOnlyAfterStaleThreshold() {
        let policy = WorkspaceModelCatalogRefreshPolicy(staleAfter: 60, retryAfterFailure: 30)

        XCTAssertFalse(policy.shouldRefresh(
            status: .liveTrustedRouter(fetchedAt: now.addingTimeInterval(-59)),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
        XCTAssertTrue(policy.shouldRefresh(
            status: .liveTrustedRouter(fetchedAt: now.addingTimeInterval(-60)),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    func testRetriesFailedRefreshAfterShortBackoff() {
        let policy = WorkspaceModelCatalogRefreshPolicy(staleAfter: 60, retryAfterFailure: 30)

        XCTAssertFalse(policy.shouldRefresh(
            status: .fallbackAfterFailure("HTTP 503", fetchedAt: now.addingTimeInterval(-29)),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
        XCTAssertTrue(policy.shouldRefresh(
            status: .fallbackAfterFailure("HTTP 503", fetchedAt: now.addingTimeInterval(-30)),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    func testMissingFetchTimeRefreshesKeyedNonBundledCatalogs() {
        let policy = WorkspaceModelCatalogRefreshPolicy()

        XCTAssertTrue(policy.shouldRefresh(
            status: ModelCatalogStatus(source: .liveTrustedRouter),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
        XCTAssertTrue(policy.shouldRefresh(
            status: ModelCatalogStatus(source: .fallbackAfterFailure, failureMessage: "timeout"),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    func testInvalidThresholdsRefreshInsteadOfDisablingCatalogUpdates() {
        XCTAssertTrue(WorkspaceModelCatalogRefreshPolicy(staleAfter: -Double.infinity).shouldRefresh(
            status: .liveTrustedRouter(fetchedAt: now),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
        XCTAssertTrue(WorkspaceModelCatalogRefreshPolicy(retryAfterFailure: Double.nan).shouldRefresh(
            status: .fallbackAfterFailure("timeout", fetchedAt: now),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }

    func testFutureFetchTimeDoesNotImmediatelyRefresh() {
        let policy = WorkspaceModelCatalogRefreshPolicy(staleAfter: -1, retryAfterFailure: -1)

        XCTAssertFalse(policy.shouldRefresh(
            status: .liveTrustedRouter(fetchedAt: now.addingTimeInterval(1)),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
        XCTAssertFalse(policy.shouldRefresh(
            status: .fallbackAfterFailure("timeout", fetchedAt: now.addingTimeInterval(1)),
            hasTrustedRouterAPIKey: true,
            now: now
        ))
    }
}
