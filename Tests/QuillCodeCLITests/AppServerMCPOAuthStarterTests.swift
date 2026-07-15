import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuillCodeCLI
import QuillCodeTools
import XCTest

final class AppServerMCPOAuthStarterTests: XCTestCase {
    func testDefaultStarterCompletesRealLoopbackFlowAndPersistsTokens() async throws {
        let httpClient = MCPOAuthStarterHTTPClient()
        let starter = DefaultAppServerMCPOAuthLoginStarter(httpClient: httpClient)
        let root = try temporaryDirectory()
        let secretStore = AppServerMCPSecretStore(
            directory: root.appendingPathComponent("secrets", isDirectory: true)
        )
        let configuration = AppServerMCPServerConfiguration(
            name: "remote",
            transport: .remote(
                url: URL(string: "https://mcp.example.com/mcp?tenant=one")!,
                headers: [
                    "X-MCP-Tenant": "tenant-one",
                    "accept": "configured-accept-must-not-win"
                ],
                bearerToken: nil
            ),
            startupTimeout: 10,
            toolTimeout: 60,
            enabledTools: nil,
            disabledTools: [],
            authStatus: .notLoggedIn,
            required: false,
            oauthClientID: "configured-client",
            oauthScopes: ["configured:read"],
            oauthResource: "https://resource.example.com"
        )

        let operation = try starter.start(
            configuration: configuration,
            requestedScopes: [],
            timeout: 3,
            secretStore: secretStore
        )
        let query = URLComponents(
            url: operation.authorizationURL,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let redirectURI = try XCTUnwrap(query.first { $0.name == "redirect_uri" }?.value)
        let state = try XCTUnwrap(query.first { $0.name == "state" }?.value)
        XCTAssertNil(query.first { $0.name == "scope" })
        XCTAssertEqual(
            query.first { $0.name == "resource" }?.value,
            "https://resource.example.com"
        )
        let redirectURL = try XCTUnwrap(URL(string: redirectURI))
        XCTAssertEqual(
            redirectURL.path,
            DefaultAppServerMCPOAuthLoginStarter.callbackPath(
                serverURL: URL(string: "https://mcp.example.com/mcp?tenant=one")!
            )
        )

        async let completion: Void = operation.waitForCompletion()
        var callback = try XCTUnwrap(
            URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)
        )
        callback.queryItems = [
            URLQueryItem(name: "code", value: "authorization-code"),
            URLQueryItem(name: "state", value: state)
        ]
        let callbackURL = try XCTUnwrap(callback.url)
        let (_, response) = try await URLSession.shared.data(from: callbackURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        try await completion

        let tokens = MCPTokenStore(
            serverID: "mcp_server:remote",
            secretStore: secretStore
        ).loadTokens()
        XCTAssertEqual(tokens?.accessToken, "stored-access-token")
        XCTAssertEqual(tokens?.refreshToken, "stored-refresh-token")
        XCTAssertTrue(httpClient.tokenRequestBody.contains("code=authorization-code"))
        XCTAssertTrue(
            httpClient.tokenRequestBody.contains(
                "resource=https%3A%2F%2Fresource.example.com"
            )
        )
        XCTAssertTrue(httpClient.requests.allSatisfy {
            $0.headers["X-MCP-Tenant"] == "tenant-one"
        })
        XCTAssertTrue(httpClient.requests.allSatisfy {
            $0.headers.first { $0.key.caseInsensitiveCompare("Accept") == .orderedSame }?.value
                == "application/json"
        })
    }

    func testCallbackPathIsStablePerServerAndSeparatesDifferentServers() {
        let first = DefaultAppServerMCPOAuthLoginStarter.callbackPath(
            serverURL: URL(string: "https://mcp.example.com/mcp?tenant=one")!
        )
        let sameWithoutFragment = DefaultAppServerMCPOAuthLoginStarter.callbackPath(
            serverURL: URL(string: "https://mcp.example.com/mcp?tenant=one#ignored")!
        )
        let different = DefaultAppServerMCPOAuthLoginStarter.callbackPath(
            serverURL: URL(string: "https://mcp.example.com/mcp?tenant=two")!
        )

        XCTAssertEqual(first, sameWithoutFragment)
        XCTAssertNotEqual(first, different)
        XCTAssertTrue(first.hasPrefix("/oauth/callback/"))
        XCTAssertEqual(first.split(separator: "/").last?.count, 12)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quillcode-mcp-oauth-starter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private final class MCPOAuthStarterHTTPClient: MCPHTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedTokenRequestBody = ""
    private var storedRequests: [MCPHTTPRequest] = []

    var tokenRequestBody: String {
        lock.lock()
        defer { lock.unlock() }
        return storedTokenRequestBody
    }

    var requests: [MCPHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        lock.lock()
        storedRequests.append(request)
        lock.unlock()
        switch request.url.path {
        case let path where path.contains("oauth-protected-resource"):
            return Self.json([
                "resource": "https://mcp.example.com/mcp",
                "authorization_servers": ["https://auth.example.com"],
                "scopes_supported": ["discovered:read"]
            ])
        case "/.well-known/oauth-authorization-server":
            return Self.json([
                "authorization_endpoint": "https://auth.example.com/authorize",
                "token_endpoint": "https://auth.example.com/token"
            ])
        case "/token":
            lock.lock()
            storedTokenRequestBody = String(decoding: request.body ?? Data(), as: UTF8.self)
            lock.unlock()
            return Self.json([
                "access_token": "stored-access-token",
                "token_type": "Bearer",
                "refresh_token": "stored-refresh-token",
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
        let body = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
            ?? Data()
        return MCPHTTPResponse(
            statusCode: 200,
            headerFields: ["content-type": "application/json"],
            body: body
        )
    }
}
