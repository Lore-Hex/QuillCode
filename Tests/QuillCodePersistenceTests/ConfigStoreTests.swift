import XCTest
import QuillCodeCore
@testable import QuillCodePersistence

final class ConfigStoreTests: PersistenceTestCase {
    func testConfigRoundTrips() throws {
        let store = try makeConfigStore()
        let config = AppConfig(
            defaultModel: "/synth",
            mode: .auto,
            apiBaseURL: "https://api.trustedrouter.com/v1",
            developerOverrideEnabled: true
        )

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
        XCTAssertEqual(config.defaultModel, TrustedRouterDefaults.synthModel)
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
            defaultModel: TrustedRouterDefaults.synthModel,
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

    func testExplicitAuthModeWinsOverLegacyDeveloperOverrideFlag() throws {
        let fileURL = try makeTempDirectory().appendingPathComponent("config.toml")
        try """
        default_model = "/synth"
        mode = "auto"
        api_base_url = "https://api.trustedrouter.com/v1"
        auth_mode = "oauth"
        developer_override_enabled = true
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let loaded = try ConfigStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded.authMode, .oauth)
        XCTAssertFalse(loaded.developerOverrideEnabled)
        XCTAssertEqual(loaded.defaultModel, TrustedRouterDefaults.synthModel)
    }
}

private extension ConfigStoreTests {
    func makeConfigStore() throws -> ConfigStore {
        try ConfigStore(fileURL: makeTempDirectory().appendingPathComponent("config.toml"))
    }
}
