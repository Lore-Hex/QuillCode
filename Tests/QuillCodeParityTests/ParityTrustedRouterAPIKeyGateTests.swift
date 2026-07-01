import XCTest

final class ParityTrustedRouterAPIKeyGateTests: QuillCodeParityTestCase {
    func testTrustedRouterAPIKeyResolutionLivesInFocusedResolver() throws {
        let client = try Self.agentSourceText(named: "TrustedRouterLLMClient.swift")
        let safetyClient = try Self.agentSourceText(named: "TrustedRouterSafetyModelClient.swift")
        let resolver = try Self.agentSourceText(named: "TrustedRouterAPIKeyResolver.swift")

        XCTAssertTrue(resolver.contains("public struct TrustedRouterAPIKeyResolver"))
        XCTAssertTrue(resolver.contains("apiKeyOverride"))
        XCTAssertTrue(resolver.contains("sessionStore?.apiKey()"))
        XCTAssertTrue(resolver.contains("nonEmptyKey"))
        XCTAssertTrue(client.contains("TrustedRouterAPIKeyResolver("))
        XCTAssertTrue(safetyClient.contains("TrustedRouterAPIKeyResolver("))

        XCTAssertFalse(client.contains("trimmingCharacters(in: .whitespacesAndNewlines)"))
        XCTAssertFalse(client.contains("sessionStore?.apiKey()"))
        XCTAssertFalse(safetyClient.contains("sessionStore?.apiKey()"))
    }
}
