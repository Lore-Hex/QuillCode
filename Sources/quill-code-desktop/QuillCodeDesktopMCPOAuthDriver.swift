import AppKit
import Foundation
import QuillCodeApp
import QuillCodeCore
import QuillCodeTools

/// Desktop driver for interactive remote-MCP OAuth sign-in. Binds a single-use loopback callback
/// server on an ephemeral port, opens the authorization URL in the user's browser, and hands the
/// captured redirect back to the platform-agnostic `WorkspaceMCPOAuthCoordinator`, which performs
/// the protocol work and persists the tokens.
@MainActor
struct QuillCodeDesktopMCPOAuthDriver {
    var secretStore: any MCPSecretStore
    var openURL: @Sendable (URL) -> Void

    init(
        secretStore: any MCPSecretStore,
        openURL: @escaping @Sendable (URL) -> Void = { url in
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
    ) {
        self.secretStore = secretStore
        self.openURL = openURL
    }

    /// Sign in to one remote MCP server. On success the tokens are stored under the server ID.
    func signIn(serverID: String, serverURL: URL, staticClientID: String?) async throws {
        let server = try Self.reserveLoopbackServer()
        try await server.start()
        defer { server.cancel() }

        let openURL = self.openURL
        let coordinator = WorkspaceMCPOAuthCoordinator(
            httpClient: URLSessionMCPHTTPClient(),
            secretStore: secretStore,
            openURL: openURL,
            awaitCallback: { _ in try await server.waitForCallback() }
        )
        try await coordinator.signIn(
            serverID: serverID,
            serverURL: serverURL,
            redirectURI: server.redirectURI,
            staticClientID: staticClientID
        )
    }

    /// Try a handful of ephemeral loopback ports until one binds. A fixed small set keeps the
    /// redirect URI predictable enough for servers that pre-register redirect URIs by port.
    private static func reserveLoopbackServer() throws -> MCPOAuthLoopbackCallbackServer {
        let candidatePorts: [UInt16] = [33418, 33419, 33420, 33421, 33422, 33423]
        var lastError: Error?
        for port in candidatePorts {
            do {
                return try MCPOAuthLoopbackCallbackServer(port: port)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? MCPOAuthLoopbackError.invalidPort
    }
}
