import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class ConfigStoreTests: PersistenceTestCase {
    func testConfigRoundTrips() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            defaultModel: "/prometheus",
            mode: .auto,
            apiBaseURL: "https://api.trustedrouter.com/v1",
            developerOverrideEnabled: true
        )

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.prometheusModel)
    }

    func testConfigDefaultsToOAuthAuthMode() throws {
        let store = try makeConfigStore()

        try store.save(AppConfig())

        let loaded = try store.load()
        XCTAssertEqual(loaded.authMode, .oauth)
        XCTAssertFalse(loaded.developerOverrideEnabled)
    }

    func testConfigRoundTripsTrustedRouterAccountProfile() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            defaultModel: TrustedRouterDefaults.prometheusModel,
            mode: .auto,
            apiBaseURL: "https://api.trustedrouter.com/v1",
            authMode: .oauth,
            trustedRouterAccount: TrustedRouterAccountProfile(
                userID: "usr_123",
                subject: "sub_quoted\"value",
                email: "quill@example.com",
                walletAddress: "0xabc"
            )
        )

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
        XCTAssertEqual(loaded.trustedRouterAccount?.displayLabel, "quill@example.com")
    }

    func testConfigRoundTripsFavoriteModels() throws {
        let store = try makeConfigStore()
        let config = AppConfig(favoriteModels: [
            " z-ai/glm-5.2 ",
            "moonshotai/kimi-k2.6",
            "z-ai/glm-5.2",
            ""
        ])

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.favoriteModels, ["z-ai/glm-5.2", "moonshotai/kimi-k2.6"])
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"favorite_model = "z-ai/glm-5.2""#))
        XCTAssertTrue(stored.contains(#"favorite_model = "moonshotai/kimi-k2.6""#))
    }

    func testConfigRoundTripsComputerUseAppApprovals() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            computerUseApprovedBundleIdentifiers: [
                " com.apple.Terminal ",
                "com.apple.Terminal",
                "com.google.Chrome"
            ],
            computerUseApprovedAppNames: [
                "Terminal",
                "terminal",
                "Google Chrome"
            ]
        )

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.computerUseApprovedBundleIdentifiers, [
            "com.apple.Terminal",
            "com.google.Chrome"
        ])
        XCTAssertEqual(loaded.computerUseApprovedAppNames, ["Terminal", "Google Chrome"])
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"computer_use_approved_bundle_identifier = "com.apple.Terminal""#))
        XCTAssertTrue(stored.contains(#"computer_use_approved_app_name = "Terminal""#))
    }

    func testConfigRoundTripsBrowserDomainPolicy() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            browserAllowedDomains: [
                " https://TrustedRouter.com/models ",
                "*.quillos.cloud",
                "trustedrouter.com"
            ],
            browserBlockedDomains: [
                "ads.example.com",
                "HTTPS://Tracker.Example/path"
            ]
        )

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.browserAllowedDomains, ["trustedrouter.com", "quillos.cloud"])
        XCTAssertEqual(loaded.browserBlockedDomains, ["ads.example.com", "tracker.example"])
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"browser_allowed_domain = "trustedrouter.com""#))
        XCTAssertTrue(stored.contains(#"browser_blocked_domain = "tracker.example""#))
    }

    func testConfigRoundTripsNotificationPreferences() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            notificationPreferences: QuillCodeNotificationPreferences(
                agentRunNotificationsEnabled: false,
                agentRunNotificationsOnlyWhenInactive: false,
                automationNotificationsEnabled: true
            )
        )

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.notificationPreferences, config.notificationPreferences)
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains("agent_run_notifications_enabled = false"))
        XCTAssertTrue(stored.contains("agent_run_notifications_only_when_inactive = false"))
        XCTAssertTrue(stored.contains("automation_notifications_enabled = true"))
    }

    func testExplicitAuthModeWinsOverLegacyDeveloperOverrideFlag() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        default_model = "/prometheus"
        mode = "auto"
        api_base_url = "https://api.trustedrouter.com/v1"
        auth_mode = "oauth"
        developer_override_enabled = true
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try ConfigStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded.authMode, .oauth)
        XCTAssertFalse(loaded.developerOverrideEnabled)
        XCTAssertEqual(loaded.defaultModel, TrustedRouterDefaults.prometheusModel)
    }
}

private extension ConfigStoreTests {
    func makeConfigStore() throws -> ConfigStore {
        try ConfigStore(fileURL: makeTempDirectory().appendingPathComponent("config.toml"))
    }
}
