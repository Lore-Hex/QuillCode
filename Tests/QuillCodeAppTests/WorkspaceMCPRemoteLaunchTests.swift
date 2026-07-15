import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class WorkspaceMCPRemoteLaunchTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/quill-workspace")

    func testHTTPManifestProducesRemoteLaunchRequest() throws {
        let manifest = remoteManifest(transport: .http, url: "https://mcp.example.com/mcp", headers: ["X-Key": "abc"])
        let request = try WorkspaceMCPLaunchRequest.make(manifest: manifest, workspaceRoot: root)
        guard case let .remote(url, headers, preferSSE, _) = request.transport else {
            return XCTFail("expected a remote transport")
        }
        XCTAssertEqual(url.absoluteString, "https://mcp.example.com/mcp")
        XCTAssertEqual(headers, ["X-Key": "abc"])
        XCTAssertFalse(preferSSE)
    }

    func testSSEManifestPrefersLegacyTransport() throws {
        let manifest = remoteManifest(transport: .sse, url: "https://mcp.example.com/sse")
        let request = try WorkspaceMCPLaunchRequest.make(manifest: manifest, workspaceRoot: root)
        guard case let .remote(_, _, preferSSE, _) = request.transport else {
            return XCTFail("expected a remote transport")
        }
        XCTAssertTrue(preferSSE)
    }

    func testHTTPManifestWithoutURLThrows() {
        let manifest = remoteManifest(transport: .http, url: nil)
        XCTAssertThrowsError(try WorkspaceMCPLaunchRequest.make(manifest: manifest, workspaceRoot: root)) {
            XCTAssertEqual($0 as? WorkspaceMCPLaunchRequestError, .missingURL(name: "Remote MCP"))
        }
    }

    func testHTTPManifestWithInvalidSchemeThrows() {
        for bad in ["ftp://x/y", "http://user:pass@host/mcp", "not a url"] {
            let manifest = remoteManifest(transport: .http, url: bad)
            XCTAssertThrowsError(
                try WorkspaceMCPLaunchRequest.make(manifest: manifest, workspaceRoot: root),
                "expected \(bad) to be rejected"
            )
        }
    }

    func testStdioManifestStillProducesStdioRequest() throws {
        let manifest = ProjectExtensionManifest(
            id: "mcp_server:fs", kind: .mcpServer, name: "FS",
            relativePath: ".quillcode/mcp/fs.json", transport: .stdio,
            launchExecutable: "mcp-server", launchArguments: ["--root", "."]
        )
        let request = try WorkspaceMCPLaunchRequest.make(manifest: manifest, workspaceRoot: root)
        guard case .stdio = request.transport else { return XCTFail("expected stdio") }
        XCTAssertEqual(request.command, "mcp-server")
    }

    func testRemoteLauncherProducesSessionAndRunningController() throws {
        let manifest = remoteManifest(transport: .http, url: "https://mcp.example.com/mcp")
        let request = try WorkspaceMCPLaunchRequest.make(manifest: manifest, workspaceRoot: root)
        let launcher = DefaultWorkspaceMCPServerLauncher(secretStore: nil, httpClient: NoopMCPHTTPClient())
        let launched = try launcher.launch(request: request) { _, _ in }
        XCTAssertTrue(launched.process.isRunning)
        XCTAssertTrue(launched.session is MCPHTTPProber)
        launched.process.terminate()
        XCTAssertFalse(launched.process.isRunning)
    }

    func testRemoteAuthResolverUsesStoredTokens() throws {
        let store = InMemoryMCPSecretStore()
        let tokenStore = MCPTokenStore(serverID: "mcp_server:remote", secretStore: store)
        try tokenStore.saveTokens(MCPOAuthTokens(accessToken: "stored-token"))
        let auth = WorkspaceMCPRemoteAuthResolver.authorization(
            serverID: "mcp_server:remote",
            serverURL: URL(string: "https://mcp.example.com/mcp")!,
            oauthClientID: nil,
            secretStore: store,
            httpClient: NoopMCPHTTPClient()
        )
        XCTAssertEqual(auth.currentAuthorizationHeader(), "Bearer stored-token")
    }

    func testRemoteAuthResolverFallsBackToNoAuthWithoutTokens() {
        let auth = WorkspaceMCPRemoteAuthResolver.authorization(
            serverID: "mcp_server:remote",
            serverURL: URL(string: "https://mcp.example.com/mcp")!,
            oauthClientID: nil,
            secretStore: InMemoryMCPSecretStore(),
            httpClient: NoopMCPHTTPClient()
        )
        XCTAssertNil(auth.currentAuthorizationHeader())
    }

    private func remoteManifest(
        transport: ProjectExtensionTransport,
        url: String?,
        headers: [String: String]? = nil
    ) -> ProjectExtensionManifest {
        ProjectExtensionManifest(
            id: "mcp_server:remote",
            kind: .mcpServer,
            name: "Remote MCP",
            relativePath: ".quillcode/mcp/remote.json",
            transport: transport,
            serverURL: url,
            headers: headers
        )
    }
}

private struct NoopMCPHTTPClient: MCPHTTPClient {
    func perform(_ request: MCPHTTPRequest) throws -> MCPHTTPResponse {
        throw MCPHTTPClientError.transport("noop")
    }
    func openStream(_ request: MCPHTTPRequest) throws -> MCPHTTPStream {
        throw MCPHTTPClientError.transport("noop")
    }
}

private final class InMemoryMCPSecretStore: MCPSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    func read(_ key: String) throws -> String? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func write(_ value: String, for key: String) throws { lock.lock(); values[key] = value; lock.unlock() }
    func delete(_ key: String) throws { lock.lock(); values[key] = nil; lock.unlock() }
}
