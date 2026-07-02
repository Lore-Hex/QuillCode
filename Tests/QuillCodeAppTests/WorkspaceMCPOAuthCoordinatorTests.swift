import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceMCPOAuthCoordinatorTests: XCTestCase {
    func testSignInDiscoversRegistersExchangesAndStoresTokens() async throws {
        let capturedAuthorizeURL = LockedURL()
        let httpClient = ScriptedMCPHTTPClient(
            capturedAuthorizeURL: capturedAuthorizeURL
        )
        let secretStore = InMemoryCoordinatorSecretStore()

        let coordinator = WorkspaceMCPOAuthCoordinator(
            httpClient: httpClient,
            secretStore: secretStore,
            openURL: { url in capturedAuthorizeURL.set(url) },
            awaitCallback: { redirectURI in
                // Simulate the browser redirecting back with the code and the flow's state.
                let state = capturedAuthorizeURL.state ?? ""
                return URL(string: "\(redirectURI)?code=auth-code&state=\(state)")!
            }
        )

        let tokens = try await coordinator.signIn(
            serverID: "mcp_server:remote",
            serverURL: URL(string: "https://mcp.example.com/mcp")!,
            redirectURI: "http://localhost:33418/callback",
            staticClientID: nil
        )

        XCTAssertEqual(tokens.accessToken, "final-access-token")
        // Tokens and the dynamic client registration are persisted under the server id.
        let tokenStore = MCPTokenStore(serverID: "mcp_server:remote", secretStore: secretStore)
        XCTAssertEqual(tokenStore.loadTokens()?.accessToken, "final-access-token")
        XCTAssertEqual(tokenStore.loadClientRegistration()?.clientID, "dyn-client")
    }

    func testSignInRejectsMismatchedCallbackState() async {
        let httpClient = ScriptedMCPHTTPClient(capturedAuthorizeURL: LockedURL())
        let coordinator = WorkspaceMCPOAuthCoordinator(
            httpClient: httpClient,
            secretStore: InMemoryCoordinatorSecretStore(),
            openURL: { _ in },
            awaitCallback: { redirectURI in
                URL(string: "\(redirectURI)?code=c&state=WRONG")!
            }
        )
        do {
            _ = try await coordinator.signIn(
                serverID: "s",
                serverURL: URL(string: "https://mcp.example.com/mcp")!,
                redirectURI: "http://localhost:33418/callback",
                staticClientID: nil
            )
            XCTFail("expected a state-mismatch error")
        } catch {
            XCTAssertEqual(error as? MCPOAuthError, .callbackStateMismatch)
        }
    }
}

/// Scripts the discovery → registration → token endpoints for the coordinator test.
private final class ScriptedMCPHTTPClient: MCPHTTPClient, @unchecked Sendable {
    let capturedAuthorizeURL: LockedURL

    init(capturedAuthorizeURL: LockedURL) {
        self.capturedAuthorizeURL = capturedAuthorizeURL
    }

    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        let path = request.url.path
        func json(_ object: [String: Any]) -> MCPHTTPResponse {
            MCPHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "application/json"],
                body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            )
        }
        if path.contains("oauth-protected-resource") {
            return json([
                "resource": "https://mcp.example.com/mcp",
                "authorization_servers": ["https://auth.example.com"]
            ])
        }
        if path.contains("oauth-authorization-server") || path.contains("openid-configuration") {
            return json([
                "authorization_endpoint": "https://auth.example.com/authorize",
                "token_endpoint": "https://auth.example.com/token",
                "registration_endpoint": "https://auth.example.com/register"
            ])
        }
        if path.contains("register") {
            return json(["client_id": "dyn-client"])
        }
        if path.contains("token") {
            let body = String(decoding: request.body ?? Data(), as: UTF8.self)
            XCTAssertTrue(body.contains("grant_type=authorization_code"))
            XCTAssertTrue(body.contains("code=auth-code"))
            return json(["access_token": "final-access-token", "token_type": "Bearer", "expires_in": 3600])
        }
        return MCPHTTPResponse(statusCode: 404)
    }

    func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        throw MCPHTTPClientError.transport("no streaming in coordinator test")
    }
}

private final class LockedURL: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?
    func set(_ url: URL) { lock.lock(); self.url = url; lock.unlock() }
    var state: String? {
        lock.lock(); defer { lock.unlock() }
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value
    }
}

private final class InMemoryCoordinatorSecretStore: MCPSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func read(_ key: String) throws -> String? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func write(_ value: String, for key: String) throws { lock.lock(); values[key] = value; lock.unlock() }
    func delete(_ key: String) throws { lock.lock(); values[key] = nil; lock.unlock() }
}
