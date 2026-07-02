import Foundation
import QuillCodeCore
import QuillCodeTools

/// Resolves how to authorize a remote MCP server at connection time, given the manifest and any
/// tokens previously stored by an interactive sign-in. This is deliberately non-interactive: it
/// never opens a browser. It picks, in order:
///   1. A stored OAuth token set (with automatic refresh on expiry/401) if one was saved.
///   2. A static `Authorization` header supplied inline in the manifest `headers`.
///   3. No auth (open server).
///
/// Interactive OAuth sign-in (browser + loopback callback) is driven separately by
/// `WorkspaceMCPOAuthCoordinator`, which writes tokens the resolver then finds here.
enum WorkspaceMCPRemoteAuthResolver {
    static func authorization(
        serverID: String,
        serverURL: URL,
        oauthClientID: String?,
        secretStore: (any MCPSecretStore)?,
        httpClient: any MCPHTTPClient
    ) -> any MCPRemoteAuthorizing {
        // A stored OAuth token set takes precedence and can self-refresh.
        guard let secretStore else { return MCPNoAuthorization() }
        let tokenStore = MCPTokenStore(serverID: serverID, secretStore: secretStore)
        guard let tokens = tokenStore.loadTokens() else {
            return MCPNoAuthorization()
        }
        if let refreshable = try? makeRefreshableAuthorization(
            serverURL: serverURL,
            oauthClientID: oauthClientID,
            tokens: tokens,
            tokenStore: tokenStore,
            httpClient: httpClient
        ) {
            return refreshable
        }
        // Even without a refresh path, use the stored access token.
        return MCPStaticAuthorization(bearerToken: tokens.accessToken)
    }

    /// Build a store-backed OAuth authorization that can refresh. Discovery is attempted so the
    /// refresh knows the token endpoint; if discovery fails we fall back to the static token.
    private static func makeRefreshableAuthorization(
        serverURL: URL,
        oauthClientID: String?,
        tokens: MCPOAuthTokens,
        tokenStore: MCPTokenStore,
        httpClient: any MCPHTTPClient
    ) throws -> any MCPRemoteAuthorizing {
        guard tokens.refreshToken != nil else {
            return MCPStaticAuthorization(bearerToken: tokens.accessToken)
        }
        let flow = MCPOAuthFlow(httpClient: httpClient)
        let configuration = try flow.discover(serverURL: serverURL)
        let clientID = tokenStore.loadClientRegistration()?.clientID
            ?? oauthClientID
            ?? ""
        return MCPStoredOAuthAuthorization(
            flow: flow,
            configuration: configuration,
            clientID: clientID,
            tokenStore: tokenStore,
            initialTokens: tokens
        )
    }
}
