import XCTest
@testable import QuillCodeApp
import QuillCodeCore

final class WorkspaceSettingsUpdateTests: XCTestCase {
    func testUnrelatedPreferenceChangesPreserveTrustedRouterAccountIdentity() {
        let config = AppConfig(
            apiBaseURL: "https://api.trustedrouter.test/v1",
            authMode: .oauth,
            developerOverrideEnabled: false
        )
        let update = WorkspaceSettingsUpdate(
            apiBaseURL: config.apiBaseURL,
            authMode: config.authMode,
            developerOverrideEnabled: config.developerOverrideEnabled,
            notificationPreferences: QuillCodeNotificationPreferences(
                agentRunNotificationsEnabled: false
            )
        )

        XCTAssertFalse(update.changesTrustedRouterAccountIdentity(comparedTo: config))
    }

    func testCredentialAndEndpointChangesInvalidateTrustedRouterAccountIdentity() {
        let config = AppConfig(
            apiBaseURL: "https://api.trustedrouter.test/v1",
            authMode: .oauth,
            developerOverrideEnabled: false
        )

        XCTAssertTrue(
            update(config, replacementAPIKey: "sk-new")
                .changesTrustedRouterAccountIdentity(comparedTo: config)
        )
        XCTAssertTrue(update(config, shouldClearAPIKey: true).changesTrustedRouterAccountIdentity(comparedTo: config))
        XCTAssertTrue(
            update(config, apiBaseURL: "https://other.trustedrouter.test/v1")
                .changesTrustedRouterAccountIdentity(comparedTo: config)
        )
        XCTAssertTrue(
            update(config, authMode: .developerOverride)
                .changesTrustedRouterAccountIdentity(comparedTo: config)
        )
    }

    private func update(
        _ config: AppConfig,
        apiBaseURL: String? = nil,
        authMode: TrustedRouterAuthMode? = nil,
        replacementAPIKey: String? = nil,
        shouldClearAPIKey: Bool = false
    ) -> WorkspaceSettingsUpdate {
        WorkspaceSettingsUpdate(
            apiBaseURL: apiBaseURL ?? config.apiBaseURL,
            authMode: authMode ?? config.authMode,
            developerOverrideEnabled: authMode == .developerOverride,
            replacementAPIKey: replacementAPIKey,
            shouldClearAPIKey: shouldClearAPIKey
        )
    }
}
