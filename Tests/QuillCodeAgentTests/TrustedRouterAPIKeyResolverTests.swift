import XCTest
@testable import QuillCodeAgent

final class TrustedRouterAPIKeyResolverTests: XCTestCase {
    func testMissingAPIKeyIsActionable() {
        let client = TrustedRouterLLMClient()
        XCTAssertThrowsError(try client.configuredAPIKey()) { error in
            XCTAssertTrue(String(describing: error).contains("Sign in"))
        }
    }

    func testAPIKeyResolverPrefersTrimmedOverride() throws {
        let resolver = TrustedRouterAPIKeyResolver(
            sessionStore: StaticTrustedRouterSessionStore(storedAPIKey: "stored-key"),
            apiKeyOverride: "  override-key\n"
        )

        XCTAssertEqual(try resolver.configuredAPIKey(), "override-key")
    }

    func testAPIKeyResolverFallsBackToTrimmedStoredKey() throws {
        let resolver = TrustedRouterAPIKeyResolver(
            sessionStore: StaticTrustedRouterSessionStore(storedAPIKey: "\nstored-key "),
            apiKeyOverride: "  "
        )

        XCTAssertEqual(try resolver.configuredAPIKey(), "stored-key")
    }

    func testAPIKeyResolverThrowsActionableMissingKeyError() {
        let resolver = TrustedRouterAPIKeyResolver(
            sessionStore: StaticTrustedRouterSessionStore(storedAPIKey: " "),
            apiKeyOverride: nil
        )

        XCTAssertThrowsError(try resolver.configuredAPIKey()) { error in
            XCTAssertTrue(String(describing: error).contains("Sign in"))
        }
    }
}

private struct StaticTrustedRouterSessionStore: TrustedRouterSessionStore {
    var storedAPIKey: String?

    func apiKey() throws -> String? {
        storedAPIKey
    }

    func saveAPIKey(_ key: String) throws {
        _ = key
    }
}
