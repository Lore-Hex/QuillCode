import Foundation
import XCTest
@testable import QuillCodeTools

final class MCPCryptoAndTokenStoreTests: XCTestCase {
    // RFC 7636 Appendix B test vector.
    func testS256ChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(MCPCrypto.s256Challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testBase64URLEncodingHasNoPaddingOrPlusSlash() {
        let data = Data([0xFB, 0xFF, 0xFE, 0x00, 0x10])
        let encoded = MCPCrypto.base64URLEncoded(data)
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
    }

    func testRandomTokensAreDistinctAndSized() {
        let a = MCPCrypto.randomToken(byteCount: 32)
        let b = MCPCrypto.randomToken(byteCount: 32)
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, 43) // 32 bytes → 43 base64url chars
    }

    func testPKCEChallengeEnforcesMinimumVerifierLength() {
        let challenge = MCPPKCEChallenge.random(byteCount: 1)
        XCTAssertGreaterThanOrEqual(challenge.codeVerifier.count, 43)
        XCTAssertEqual(challenge.method, "S256")
    }

    func testTokenExpiryWithSkew() {
        let expiring = MCPOAuthTokens(accessToken: "x", expiresAt: Date().addingTimeInterval(10))
        XCTAssertTrue(expiring.isExpired(skew: 30))
        let fresh = MCPOAuthTokens(accessToken: "x", expiresAt: Date().addingTimeInterval(3600))
        XCTAssertFalse(fresh.isExpired())
        let noExpiry = MCPOAuthTokens(accessToken: "x")
        XCTAssertFalse(noExpiry.isExpired())
    }

    func testAuthorizationHeaderNormalizesTokenType() {
        XCTAssertEqual(MCPOAuthTokens(accessToken: "abc", tokenType: "bearer").authorizationHeaderValue, "Bearer abc")
        XCTAssertEqual(MCPOAuthTokens(accessToken: "abc", tokenType: "").authorizationHeaderValue, "Bearer abc")
    }

    func testTokenStoreRoundTrips() throws {
        let store = InMemorySecretStore()
        let tokenStore = MCPTokenStore(serverID: "mcp_server:acme", secretStore: store)
        XCTAssertNil(tokenStore.loadTokens())

        let tokens = MCPOAuthTokens(
            accessToken: "at",
            tokenType: "Bearer",
            refreshToken: "rt",
            expiresAt: Date(timeIntervalSince1970: 1_000_000),
            scope: "mcp:read"
        )
        try tokenStore.saveTokens(tokens)
        let loaded = tokenStore.loadTokens()
        XCTAssertEqual(loaded?.accessToken, "at")
        XCTAssertEqual(loaded?.refreshToken, "rt")
        XCTAssertEqual(loaded?.expiresAt, Date(timeIntervalSince1970: 1_000_000))

        try tokenStore.clearTokens()
        XCTAssertNil(tokenStore.loadTokens())
    }

    func testClientRegistrationRoundTrips() throws {
        let store = InMemorySecretStore()
        let tokenStore = MCPTokenStore(serverID: "s", secretStore: store)
        try tokenStore.saveClientRegistration(MCPDynamicClientRegistration(clientID: "cid", clientSecret: "sec"))
        XCTAssertEqual(tokenStore.loadClientRegistration()?.clientID, "cid")
    }

    func testSecretKeysAreFilenameSafe() {
        let key = MCPSecretKeys.tokens(serverID: "mcp_server:acme/../etc")
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.contains(":"))
    }

    func testStoredOAuthAuthorizationRefreshesOn401Path() throws {
        // A provider with an expired token and a refresh token refreshes when asked.
        let httpClient = MCPHTTPStubClient()
        httpClient.onPerform { _ in
            let payload = [
                "access_token": "refreshed",
                "token_type": "Bearer",
                "expires_in": 3600
            ] as [String: Any]
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
                return MCPHTTPResponse(statusCode: 500)
            }
            return MCPHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "application/json"],
                body: body
            )
        }
        let store = InMemorySecretStore()
        let tokenStore = MCPTokenStore(serverID: "s", secretStore: store)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!
        )
        let provider = MCPStoredOAuthAuthorization(
            flow: MCPOAuthFlow(httpClient: httpClient),
            configuration: configuration,
            clientID: "c",
            tokenStore: tokenStore,
            initialTokens: MCPOAuthTokens(
                accessToken: "old",
                refreshToken: "rt",
                expiresAt: Date().addingTimeInterval(-10)
            )
        )
        XCTAssertEqual(provider.refreshAuthorizationHeader(), "Bearer refreshed")
        // The refreshed token is persisted.
        XCTAssertEqual(tokenStore.loadTokens()?.accessToken, "refreshed")
    }

    func testStoredOAuthAuthorizationReturnsNilWithoutRefreshToken() {
        let store = InMemorySecretStore()
        let provider = MCPStoredOAuthAuthorization(
            flow: MCPOAuthFlow(httpClient: MCPHTTPStubClient()),
            configuration: MCPOAuthConfiguration(
                authorizationEndpoint: URL(string: "https://a/authorize")!,
                tokenEndpoint: URL(string: "https://a/token")!
            ),
            clientID: "c",
            tokenStore: MCPTokenStore(serverID: "s", secretStore: store),
            initialTokens: MCPOAuthTokens(accessToken: "only")
        )
        XCTAssertNil(provider.refreshAuthorizationHeader())
    }
}

final class InMemorySecretStore: MCPSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(_ key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func write(_ value: String, for key: String) throws {
        lock.lock(); values[key] = value; lock.unlock()
    }

    func delete(_ key: String) throws {
        lock.lock(); values[key] = nil; lock.unlock()
    }
}
