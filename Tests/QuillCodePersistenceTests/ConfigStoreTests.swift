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

    func testConfigRoundTripsCodeReviewSettings() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            reviewModel: " /prometheus ",
            reviewDelivery: .detached
        )

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.reviewModel, TrustedRouterDefaults.prometheusModel)
        XCTAssertEqual(loaded.reviewDelivery, .detached)
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"review_model = "trustedrouter/fusion""#))
        XCTAssertTrue(stored.contains(#"review_delivery = "detached""#))
    }

    func testConfigWithoutCodeReviewKeysLoadsCurrentModelDefaults() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        default_model = "/prometheus"
        mode = "auto"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try ConfigStore(fileURL: fileURL).load()

        XCTAssertNil(loaded.reviewModel)
        XCTAssertEqual(loaded.reviewDelivery, .current)
    }

    func testConfigNormalizesBlankReviewModelAndIgnoresUnknownDelivery() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        review_model = "  "
        review_delivery = "background"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try ConfigStore(fileURL: fileURL).load()

        XCTAssertNil(loaded.reviewModel)
        XCTAssertEqual(loaded.reviewDelivery, .current)
    }

    func testConfigOmitsInheritedReviewModelAndWritesCurrentDelivery() throws {
        let store = try makeConfigStore()

        try store.save(AppConfig())

        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(stored.contains("review_model ="))
        XCTAssertTrue(stored.contains(#"review_delivery = "current""#))
    }

    func testConfigRoundTripsManagedWorktreeSettings() throws {
        let store = try makeConfigStore()
        let config = AppConfig(managedWorktrees: ManagedWorktreeSettings(
            rootPath: "~/QuillCode Tasks",
            automaticCleanupEnabled: false,
            retentionLimit: 42
        ))

        try store.save(config)

        XCTAssertEqual(try store.load().managedWorktrees, config.managedWorktrees)
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"managed_worktree_root = "~/QuillCode Tasks""#))
        XCTAssertTrue(stored.contains("managed_worktree_automatic_cleanup_enabled = false"))
        XCTAssertTrue(stored.contains("managed_worktree_retention_limit = 42"))
    }

    func testConfigNormalizesInvalidManagedWorktreeValues() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        managed_worktree_root = "relative/path"
        managed_worktree_automatic_cleanup_enabled = nope
        managed_worktree_retention_limit = 0
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let settings = try ConfigStore(fileURL: fileURL).load().managedWorktrees

        XCTAssertNil(settings.rootPath)
        XCTAssertTrue(settings.automaticCleanupEnabled)
        XCTAssertEqual(settings.retentionLimit, 1)
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

    func testConfigRoundTripsDisabledSkillSelectors() throws {
        let store = try makeConfigStore()
        let manifest = store.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("skills/review/SKILL.md")
        try FileManager.default.createDirectory(
            at: manifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "skill".write(to: manifest, atomically: true, encoding: .utf8)
        let config = AppConfig(skillConfiguration: SkillConfiguration(
            disabledPaths: [manifest.path],
            disabledNames: ["browser-use"]
        ))

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.skillConfiguration, config.skillConfiguration)
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"disabled_skill_path = "#))
        XCTAssertTrue(stored.contains(#"disabled_skill_name = "browser-use""#))
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

    func testConfigRoundTripsValuesContainingNewlinesAndEscapes() throws {
        // Regression: a value with a newline was written as a PHYSICAL line break, so load() hit an
        // '='-less fragment and threw invalidLine — discarding the ENTIRE config (model, mode, auth,
        // account, notification prefs). Now newline/CR/quote/backslash round-trip losslessly.
        let store = try makeConfigStore()
        let gnarly = "line1\nline2\r\ttab \"quoted\" back\\slash \\n literal"
        let config = AppConfig(
            defaultModel: TrustedRouterDefaults.prometheusModel,
            apiBaseURL: gnarly,
            authMode: .oauth,
            trustedRouterAccount: TrustedRouterAccountProfile(userID: "u", subject: gnarly)
        )

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded.apiBaseURL, gnarly)
        XCTAssertEqual(loaded.trustedRouterAccount?.subject, gnarly)
        XCTAssertEqual(loaded, config)

        // On disk the value stays on one logical line (newline escaped as \n), so no '='-less
        // fragment can ever brick the parser again.
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains(#"api_base_url = "line1\nline2"#))
        XCTAssertFalse(stored.contains("line1\nline2"))
    }

    func testConfigRoundTripsRunSpendLimits() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            runSpendFuseUSD: 2.50,
            runSpendPeriodLimits: RunSpendPeriodLimits(
                dailyUSD: 5,
                weeklyUSD: 12.5,
                monthlyUSD: 30
            )
        )

        try store.save(config)

        let loaded = try store.load()
        XCTAssertEqual(loaded.runSpendFuseUSD, 2.50)
        XCTAssertEqual(loaded.runSpendPeriodLimits.dailyUSD, 5)
        XCTAssertEqual(loaded.runSpendPeriodLimits.weeklyUSD, 12.5)
        XCTAssertEqual(loaded.runSpendPeriodLimits.monthlyUSD, 30)

        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains("run_spend_fuse_usd = 2.500000"))
        XCTAssertTrue(stored.contains("run_spend_daily_limit_usd = 5.000000"))
        XCTAssertTrue(stored.contains("run_spend_weekly_limit_usd = 12.500000"))
        XCTAssertTrue(stored.contains("run_spend_monthly_limit_usd = 30.000000"))
    }

    func testConfigIgnoresInvalidRunSpendLimits() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        run_spend_fuse_usd = -1
        run_spend_daily_limit_usd = 0
        run_spend_weekly_limit_usd = nope
        run_spend_monthly_limit_usd = 15
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try ConfigStore(fileURL: fileURL).load()

        XCTAssertNil(loaded.runSpendFuseUSD)
        XCTAssertNil(loaded.runSpendPeriodLimits.dailyUSD)
        XCTAssertNil(loaded.runSpendPeriodLimits.weeklyUSD)
        XCTAssertEqual(loaded.runSpendPeriodLimits.monthlyUSD, 15)
    }

    func testConfigRoundTripsMaxToolSteps() throws {
        let store = try makeConfigStore()

        try store.save(AppConfig(maxToolSteps: 128))
        XCTAssertEqual(try store.load().maxToolSteps, 128)
        let stored = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(stored.contains("max_tool_steps = 128"))
    }

    func testConfigWithoutMaxToolStepsKeyLoadsProductionDefault() throws {
        // A legacy config file written before max_tool_steps existed must load the production
        // default (64), NOT the conservative library default (6) that strangles real tasks.
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        default_model = "/prometheus"
        mode = "auto"
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(try ConfigStore(fileURL: fileURL).load().maxToolSteps, AppConfig.defaultMaxToolSteps)
    }

    func testConfigClampsNonPositiveMaxToolSteps() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        max_tool_steps = 0
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(try ConfigStore(fileURL: fileURL).load().maxToolSteps, 1)
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
