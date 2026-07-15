import Foundation

/// Resolves non-interactive authorization for a configured remote MCP server.
///
/// Interactive OAuth flows persist tokens through `MCPTokenStore`; later desktop and app-server
/// connections use this resolver to load the same credentials and refresh them when possible.
/// The resolver never opens a browser and never exposes token material to callers.
public enum MCPRemoteAuthorizationResolver {
    public static func authorization(
        serverID: String,
        serverURL: URL,
        oauthClientID: String?,
        oauthScopes: [String] = [],
        oauthResource: String? = nil,
        serverHeaders: [String: String] = [:],
        secretStore: (any MCPSecretStore)?,
        httpClient: any MCPHTTPClient
    ) -> any MCPRemoteAuthorizing {
        guard let secretStore else { return MCPNoAuthorization() }
        let tokenStore = MCPTokenStore(serverID: serverID, secretStore: secretStore)
        guard let tokens = tokenStore.loadTokens() else { return MCPNoAuthorization() }
        let configuredClientID = oauthClientID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clientID = configuredClientID.flatMap { $0.isEmpty ? nil : $0 }
            ?? tokenStore.loadClientRegistration()?.clientID
        let oauthHTTPClient = MCPHTTPHeaderInjectingClient(
            base: httpClient,
            additionalHeaders: serverHeaders
        )

        guard tokens.refreshToken != nil,
              let clientID,
              !clientID.isEmpty,
              let authorization = try? refreshableAuthorization(
                  serverURL: serverURL,
                  clientID: clientID,
                  oauthScopes: oauthScopes,
                  oauthResource: oauthResource,
                  tokens: tokens,
                  tokenStore: tokenStore,
                  httpClient: oauthHTTPClient
              )
        else {
            return MCPStaticAuthorization(bearerToken: tokens.accessToken)
        }
        return authorization
    }

    public static func hasStoredTokens(
        serverID: String,
        secretStore: (any MCPSecretStore)?
    ) -> Bool {
        guard let secretStore else { return false }
        return MCPTokenStore(serverID: serverID, secretStore: secretStore).loadTokens() != nil
    }

    private static func refreshableAuthorization(
        serverURL: URL,
        clientID: String,
        oauthScopes: [String],
        oauthResource: String?,
        tokens: MCPOAuthTokens,
        tokenStore: MCPTokenStore,
        httpClient: any MCPHTTPClient
    ) throws -> any MCPRemoteAuthorizing {
        let flow = MCPOAuthFlow(httpClient: httpClient)
        var configuration = try flow.discover(serverURL: serverURL)
        if !oauthScopes.isEmpty { configuration.scopesSupported = oauthScopes }
        if let oauthResource, !oauthResource.isEmpty { configuration.resource = oauthResource }
        return MCPStoredOAuthAuthorization(
            flow: flow,
            configuration: configuration,
            clientID: clientID,
            tokenStore: tokenStore,
            initialTokens: tokens
        )
    }
}
