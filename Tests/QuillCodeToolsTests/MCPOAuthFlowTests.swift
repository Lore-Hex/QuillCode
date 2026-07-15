import Foundation
import XCTest
@testable import QuillCodeTools

final class MCPOAuthFlowTests: XCTestCase {
    private let serverURL = URL(string: "https://mcp.example.com/mcp")!

    // MARK: Discovery

    func testDiscoveryFollowsProtectedResourceToAuthorizationServer() throws {
        let client = MCPHTTPStubClient()
        client.onPerform { request in
            let path = request.url.path
            if path.contains("oauth-protected-resource") {
                return Self.json([
                    "resource": "https://mcp.example.com/mcp",
                    "authorization_servers": ["https://auth.example.com"],
                    "scopes_supported": ["mcp:read", "mcp:write"]
                ])
            }
            if path.contains("oauth-authorization-server") || path.contains("openid-configuration") {
                XCTAssertTrue(request.url.absoluteString.hasPrefix("https://auth.example.com"))
                return Self.json([
                    "issuer": "https://auth.example.com",
                    "authorization_endpoint": "https://auth.example.com/authorize",
                    "token_endpoint": "https://auth.example.com/token",
                    "registration_endpoint": "https://auth.example.com/register"
                ])
            }
            return MCPHTTPResponse(statusCode: 404)
        }

        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = try flow.discover(serverURL: serverURL)
        XCTAssertEqual(configuration.authorizationEndpoint.absoluteString, "https://auth.example.com/authorize")
        XCTAssertEqual(configuration.tokenEndpoint.absoluteString, "https://auth.example.com/token")
        XCTAssertEqual(configuration.registrationEndpoint?.absoluteString, "https://auth.example.com/register")
        XCTAssertEqual(configuration.scopesSupported, ["mcp:read", "mcp:write"])
    }

    func testDiscoveryFallsBackToServerOriginWhenNoProtectedResourceMetadata() throws {
        let client = MCPHTTPStubClient()
        client.onPerform { request in
            if request.url.path.contains("oauth-protected-resource") {
                return MCPHTTPResponse(statusCode: 404)
            }
            if request.url.path.contains("oauth-authorization-server") {
                return Self.json([
                    "authorization_endpoint": "https://mcp.example.com/authorize",
                    "token_endpoint": "https://mcp.example.com/token"
                ])
            }
            return MCPHTTPResponse(statusCode: 404)
        }
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = try flow.discover(serverURL: serverURL)
        XCTAssertEqual(configuration.tokenEndpoint.absoluteString, "https://mcp.example.com/token")
    }

    // MARK: Dynamic client registration

    func testDynamicRegistrationPostsAndDecodesClientID() throws {
        let client = MCPHTTPStubClient()
        client.onPerform { request in
            XCTAssertEqual(request.method, "POST")
            let body = try XCTUnwrap(request.body)
            let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual((object?["redirect_uris"] as? [String])?.first, "http://localhost:33418/callback")
            return Self.json(["client_id": "dyn-123", "client_secret": "shh"])
        }
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a.example.com/authorize")!,
            tokenEndpoint: URL(string: "https://a.example.com/token")!,
            registrationEndpoint: URL(string: "https://a.example.com/register")!
        )
        let registration = try flow.registerClientIfNeeded(
            configuration: configuration,
            redirectURI: "http://localhost:33418/callback",
            existing: nil,
            staticClientID: nil
        )
        XCTAssertEqual(registration.clientID, "dyn-123")
        XCTAssertEqual(registration.clientSecret, "shh")
        XCTAssertEqual(registration.redirectURIs, ["http://localhost:33418/callback"])
    }

    func testRegistrationPrefersStaticClientIDAndReusesMatchingDynamicRegistration() throws {
        let client = MCPHTTPStubClient()
        client.onPerform { _ in XCTFail("must not call the network"); return MCPHTTPResponse(statusCode: 500) }
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!,
            registrationEndpoint: URL(string: "https://a/register")!
        )
        let fromStatic = try flow.registerClientIfNeeded(
            configuration: configuration, redirectURI: "http://localhost/cb", existing: nil, staticClientID: "static-1"
        )
        XCTAssertEqual(fromStatic.clientID, "static-1")
        XCTAssertEqual(fromStatic.redirectURIs, ["http://localhost/cb"])

        let existing = MCPDynamicClientRegistration(
            clientID: "existing-1",
            redirectURIs: ["http://localhost/cb"]
        )
        let fromExisting = try flow.registerClientIfNeeded(
            configuration: configuration, redirectURI: "http://localhost/cb", existing: existing, staticClientID: nil
        )
        XCTAssertEqual(fromExisting.clientID, "existing-1")
    }

    func testDynamicRegistrationRefreshesWhenRedirectChanges() throws {
        let client = MCPHTTPStubClient()
        client.onPerform { request in
            let body = try XCTUnwrap(request.body)
            let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            XCTAssertEqual(object?["redirect_uris"] as? [String], ["http://localhost:33419/callback"])
            return Self.json(["client_id": "replacement"])
        }
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!,
            registrationEndpoint: URL(string: "https://a/register")!
        )
        let existing = MCPDynamicClientRegistration(
            clientID: "stale",
            redirectURIs: ["http://localhost:33418/callback"]
        )

        let refreshed = try flow.registerClientIfNeeded(
            configuration: configuration,
            redirectURI: "http://localhost:33419/callback",
            existing: existing,
            staticClientID: nil
        )

        XCTAssertEqual(refreshed.clientID, "replacement")
        XCTAssertEqual(refreshed.redirectURIs, ["http://localhost:33419/callback"])
    }

    func testRegistrationUnavailableThrows() {
        let client = MCPHTTPStubClient()
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!,
            registrationEndpoint: nil
        )
        XCTAssertThrowsError(try flow.registerClientIfNeeded(
            configuration: configuration, redirectURI: "http://localhost/cb", existing: nil, staticClientID: nil
        ))
    }

    func testRegistrationWithoutEndpointReusesOnlyLegacyUnknownRedirect() throws {
        let flow = MCPOAuthFlow(httpClient: MCPHTTPStubClient())
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!,
            registrationEndpoint: nil
        )
        let legacy = MCPDynamicClientRegistration(clientID: "legacy-client")
        let legacyResult = try flow.registerClientIfNeeded(
            configuration: configuration,
            redirectURI: "http://localhost:33419/callback",
            existing: legacy,
            staticClientID: nil
        )
        XCTAssertEqual(legacyResult.clientID, "legacy-client")

        let stale = MCPDynamicClientRegistration(
            clientID: "stale-client",
            redirectURIs: ["http://localhost:33418/callback"]
        )
        XCTAssertThrowsError(try flow.registerClientIfNeeded(
            configuration: configuration,
            redirectURI: "http://localhost:33419/callback",
            existing: stale,
            staticClientID: nil
        )) { error in
            XCTAssertEqual(error as? MCPOAuthError, .registrationUnavailable)
        }
    }

    // MARK: Authorization URL + callback

    func testAuthorizationURLCarriesPKCEStateAndResource() throws {
        let flow = MCPOAuthFlow(httpClient: MCPHTTPStubClient())
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a.example.com/authorize")!,
            tokenEndpoint: URL(string: "https://a.example.com/token")!,
            resource: "https://mcp.example.com/mcp",
            scopesSupported: ["mcp:read"]
        )
        let authorization = try flow.makeAuthorization(
            configuration: configuration, clientID: "client-1", redirectURI: "http://localhost:33418/callback"
        )
        let items = URLComponents(url: authorization.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "client-1")
        XCTAssertEqual(value("redirect_uri"), "http://localhost:33418/callback")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("scope"), "mcp:read")
        XCTAssertEqual(value("resource"), "https://mcp.example.com/mcp")
        XCTAssertFalse((value("code_challenge") ?? "").isEmpty)
        XCTAssertFalse((value("state") ?? "").isEmpty)
        // State is random per call, not a fixed nonce.
        let second = try flow.makeAuthorization(
            configuration: configuration, clientID: "client-1", redirectURI: "http://localhost:33418/callback"
        )
        XCTAssertNotEqual(authorization.state, second.state)
        XCTAssertNotEqual(authorization.codeVerifier, second.codeVerifier)
    }

    func testParseCallbackValidatesState() throws {
        let flow = MCPOAuthFlow(httpClient: MCPHTTPStubClient())
        let good = URL(string: "http://localhost:33418/callback?code=abc&state=xyz")!
        XCTAssertEqual(try flow.parseCallback(good, expectedState: "xyz"), "abc")

        let mismatched = URL(string: "http://localhost:33418/callback?code=abc&state=nope")!
        XCTAssertThrowsError(try flow.parseCallback(mismatched, expectedState: "xyz")) {
            XCTAssertEqual($0 as? MCPOAuthError, .callbackStateMismatch)
        }

        let errorCallback = URL(string: "http://localhost:33418/callback?error=access_denied&state=xyz")!
        XCTAssertThrowsError(try flow.parseCallback(errorCallback, expectedState: "xyz"))
    }

    // MARK: Token exchange + refresh

    func testExchangeCodeDecodesTokens() throws {
        let client = MCPHTTPStubClient()
        client.onPerform { request in
            XCTAssertEqual(request.method, "POST")
            let bodyText = String(decoding: request.body ?? Data(), as: UTF8.self)
            XCTAssertTrue(bodyText.contains("grant_type=authorization_code"))
            XCTAssertTrue(bodyText.contains("code_verifier="))
            return Self.json([
                "access_token": "at-1",
                "token_type": "Bearer",
                "refresh_token": "rt-1",
                "expires_in": 3600
            ])
        }
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!
        )
        let tokens = try flow.exchangeCode(
            configuration: configuration, clientID: "c", redirectURI: "http://localhost/cb",
            code: "code-1", codeVerifier: "verifier-1"
        )
        XCTAssertEqual(tokens.accessToken, "at-1")
        XCTAssertEqual(tokens.refreshToken, "rt-1")
        XCTAssertEqual(tokens.authorizationHeaderValue, "Bearer at-1")
        XCTAssertNotNil(tokens.expiresAt)
    }

    func testRefreshRetainsPriorRefreshTokenWhenOmitted() throws {
        let client = MCPHTTPStubClient()
        client.onPerform { _ in
            Self.json(["access_token": "at-2", "token_type": "Bearer", "expires_in": 60])
        }
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!
        )
        let tokens = try flow.refresh(configuration: configuration, clientID: "c", refreshToken: "rt-old")
        XCTAssertEqual(tokens.accessToken, "at-2")
        XCTAssertEqual(tokens.refreshToken, "rt-old", "a refresh omitting the refresh_token keeps the old one")
    }

    func testExchangeFailureThrows() {
        let client = MCPHTTPStubClient()
        client.onPerform { _ in MCPHTTPResponse(statusCode: 400, body: Data("{\"error\":\"invalid_grant\"}".utf8)) }
        let flow = MCPOAuthFlow(httpClient: client)
        let configuration = MCPOAuthConfiguration(
            authorizationEndpoint: URL(string: "https://a/authorize")!,
            tokenEndpoint: URL(string: "https://a/token")!
        )
        XCTAssertThrowsError(try flow.exchangeCode(
            configuration: configuration, clientID: "c", redirectURI: "http://localhost/cb",
            code: "bad", codeVerifier: "v"
        ))
    }

    // MARK: URL validation / SSRF-ish

    func testOriginRejectsNonHTTPScheme() {
        XCTAssertThrowsError(try MCPOAuthFlow.origin(of: URL(string: "ftp://x/y")!))
        XCTAssertThrowsError(try MCPOAuthFlow.origin(of: URL(string: "file:///etc/passwd")!))
    }

    func testFormURLEncodingEscapesReserved() {
        let encoded = MCPOAuthFlow.formURLEncoded(["a b": "c&d", "z": "1"])
        XCTAssertEqual(encoded, "a%20b=c%26d&z=1")
    }

    // MARK: Helpers

    private static func json(_ object: [String: Any], statusCode: Int = 200) -> MCPHTTPResponse {
        MCPHTTPResponse(
            statusCode: statusCode,
            headerFields: ["content-type": "application/json"],
            body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        )
    }
}
