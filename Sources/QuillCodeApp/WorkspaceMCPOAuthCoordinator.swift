import Foundation
import QuillCodeCore
import QuillCodeTools

/// Orchestrates an interactive OAuth 2.1 sign-in for a remote MCP server and persists the
/// resulting tokens (and any dynamic-registration client ID) into the secret store, where the
/// connection-time `WorkspaceMCPRemoteAuthResolver` then finds them.
///
/// This coordinator owns only the protocol logic (discovery → registration → authorize URL →
/// exchange). The two platform-bound steps — opening a browser and receiving the redirect on a
/// loopback listener — are injected, so the whole flow is testable against a stub HTTP client and
/// a synthetic callback URL with NO real network or browser.
public struct WorkspaceMCPOAuthCoordinator: Sendable {
    /// Opens the authorization URL in the user's browser.
    public typealias OpenURL = @Sendable (URL) -> Void
    /// Starts a loopback listener bound to `redirectURI` and returns the full callback URL once
    /// the browser redirects to it.
    public typealias AwaitCallback = @Sendable (_ redirectURI: String) async throws -> URL

    private let flow: MCPOAuthFlow
    private let secretStore: any MCPSecretStore
    private let openURL: OpenURL
    private let awaitCallback: AwaitCallback

    public init(
        httpClient: any MCPHTTPClient,
        secretStore: any MCPSecretStore,
        openURL: @escaping OpenURL,
        awaitCallback: @escaping AwaitCallback,
        clientName: String = "QuillCode"
    ) {
        self.flow = MCPOAuthFlow(httpClient: httpClient, clientName: clientName)
        self.secretStore = secretStore
        self.openURL = openURL
        self.awaitCallback = awaitCallback
    }

    /// Run the full sign-in for one server. `redirectURI` is the loopback callback the injected
    /// listener will serve (e.g. `http://localhost:33418/callback`). On success the tokens are
    /// persisted and returned.
    @discardableResult
    public func signIn(
        serverID: String,
        serverURL: URL,
        redirectURI: String,
        staticClientID: String?
    ) async throws -> MCPOAuthTokens {
        let tokenStore = MCPTokenStore(serverID: serverID, secretStore: secretStore)

        let configuration = try flow.discover(serverURL: serverURL)
        let registration = try flow.registerClientIfNeeded(
            configuration: configuration,
            redirectURI: redirectURI,
            existing: tokenStore.loadClientRegistration(),
            staticClientID: staticClientID
        )
        try? tokenStore.saveClientRegistration(registration)

        let authorization = try flow.makeAuthorization(
            configuration: configuration,
            clientID: registration.clientID,
            redirectURI: redirectURI,
            scopes: configuration.scopesSupported
        )

        openURL(authorization.authorizationURL)
        let callbackURL = try await awaitCallback(redirectURI)
        let code = try flow.parseCallback(callbackURL, expectedState: authorization.state)

        let tokens = try flow.exchangeCode(
            configuration: configuration,
            clientID: registration.clientID,
            redirectURI: redirectURI,
            code: code,
            codeVerifier: authorization.codeVerifier
        )
        try tokenStore.saveTokens(tokens)
        return tokens
    }
}
