import Foundation
@testable import QuillCodeTools
import XCTest

final class MCPRemoteAuthorizationResolverTests: XCTestCase {
    func testRefreshPrefersConfiguredClientAndCarriesServerHeaders() throws {
        let secretStore = ResolverSecretStore()
        let tokenStore = MCPTokenStore(serverID: "mcp_server:remote", secretStore: secretStore)
        try tokenStore.saveTokens(MCPOAuthTokens(
            accessToken: "expired-access",
            refreshToken: "refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1)
        ))
        try tokenStore.saveClientRegistration(MCPDynamicClientRegistration(
            clientID: "stale-dynamic-client",
            redirectURIs: ["http://localhost/old"]
        ))
        let httpClient = ResolverOAuthHTTPClient()

        let authorization = MCPRemoteAuthorizationResolver.authorization(
            serverID: "mcp_server:remote",
            serverURL: URL(string: "https://mcp.example.com/mcp")!,
            oauthClientID: "configured-static-client",
            oauthScopes: ["tools:read"],
            oauthResource: "https://resource.example.com",
            serverHeaders: ["X-MCP-Tenant": "tenant-one"],
            secretStore: secretStore,
            httpClient: httpClient
        )

        XCTAssertEqual(authorization.currentAuthorizationHeader(), "Bearer refreshed-access")
        let tokenRequest = try XCTUnwrap(httpClient.requests.last)
        let body = String(decoding: tokenRequest.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("client_id=configured-static-client"))
        XCTAssertFalse(body.contains("stale-dynamic-client"))
        XCTAssertTrue(body.contains("scope=tools%3Aread"))
        XCTAssertTrue(body.contains("resource=https%3A%2F%2Fresource.example.com"))
        XCTAssertTrue(httpClient.requests.allSatisfy {
            $0.headers["X-MCP-Tenant"] == "tenant-one"
        })
    }

    func testRefreshTokenWithoutClientIDFallsBackToCurrentAccessTokenWithoutNetwork() throws {
        let secretStore = ResolverSecretStore()
        let tokenStore = MCPTokenStore(serverID: "mcp_server:remote", secretStore: secretStore)
        try tokenStore.saveTokens(MCPOAuthTokens(
            accessToken: "current-access",
            refreshToken: "refresh-token"
        ))
        let httpClient = ResolverOAuthHTTPClient()

        let authorization = MCPRemoteAuthorizationResolver.authorization(
            serverID: "mcp_server:remote",
            serverURL: URL(string: "https://mcp.example.com/mcp")!,
            oauthClientID: nil,
            secretStore: secretStore,
            httpClient: httpClient
        )

        XCTAssertEqual(authorization.currentAuthorizationHeader(), "Bearer current-access")
        XCTAssertTrue(httpClient.requests.isEmpty)
    }
}

private final class ResolverOAuthHTTPClient: MCPHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequests: [MCPHTTPRequest] = []

    var requests: [MCPHTTPRequest] {
        lock.withLock { storedRequests }
    }

    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        lock.withLock { storedRequests.append(request) }
        switch request.url.path {
        case let path where path.contains("oauth-protected-resource"):
            return Self.json([
                "resource": "https://mcp.example.com/mcp",
                "authorization_servers": ["https://auth.example.com"]
            ])
        case "/.well-known/oauth-authorization-server":
            return Self.json([
                "authorization_endpoint": "https://auth.example.com/authorize",
                "token_endpoint": "https://auth.example.com/token"
            ])
        case "/token":
            return Self.json([
                "access_token": "refreshed-access",
                "token_type": "Bearer",
                "refresh_token": "refreshed-token",
                "expires_in": 3_600
            ])
        default:
            return MCPHTTPResponse(statusCode: 404)
        }
    }

    func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        _ = request
        throw MCPHTTPClientError.transport("unexpected stream")
    }

    private static func json(_ value: [String: Any]) -> MCPHTTPResponse {
        MCPHTTPResponse(
            statusCode: 200,
            headerFields: ["content-type": "application/json"],
            body: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
                ?? Data()
        )
    }
}

private final class ResolverSecretStore: MCPSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func read(_ key: String) throws -> String? {
        lock.withLock { values[key] }
    }

    func write(_ value: String, for key: String) throws {
        lock.withLock { values[key] = value }
    }

    func delete(_ key: String) throws {
        lock.withLock { values[key] = nil }
    }
}
