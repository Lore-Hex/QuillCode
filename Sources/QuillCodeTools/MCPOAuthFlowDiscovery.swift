import Foundation

extension MCPOAuthFlow {
    // MARK: Discovery

    /// Resolve the OAuth endpoints for a server given its MCP endpoint URL (e.g. the same URL
    /// used for the transport). Follows protected-resource metadata to the authorization server.
    public func discover(serverURL: URL) throws -> MCPOAuthConfiguration {
        let origin = try Self.origin(of: serverURL)
        let resourceMetadata = fetchProtectedResourceMetadata(origin: origin, serverURL: serverURL)

        let authServerURLString = resourceMetadata?.authorizationServers?.first
        let authServerBase: URL
        if let authServerURLString, let url = URL(string: authServerURLString) {
            authServerBase = url
        } else {
            // Fall back to treating the server's own origin as the authorization server, which
            // is the common single-tenant case.
            authServerBase = origin
        }

        guard let serverMetadata = fetchAuthorizationServerMetadata(base: authServerBase) else {
            throw MCPOAuthError.discoveryFailed("could not load authorization server metadata")
        }
        guard let authorizeString = serverMetadata.authorizationEndpoint,
              let authorizeURL = URL(string: authorizeString) else {
            throw MCPOAuthError.missingEndpoint("authorization_endpoint")
        }
        guard let tokenString = serverMetadata.tokenEndpoint,
              let tokenURL = URL(string: tokenString) else {
            throw MCPOAuthError.missingEndpoint("token_endpoint")
        }
        let registrationURL = serverMetadata.registrationEndpoint.flatMap(URL.init(string:))
        return MCPOAuthConfiguration(
            authorizationEndpoint: authorizeURL,
            tokenEndpoint: tokenURL,
            registrationEndpoint: registrationURL,
            resource: resourceMetadata?.resource ?? origin.absoluteString,
            scopesSupported: resourceMetadata?.scopesSupported
                ?? serverMetadata.scopesSupported
                ?? []
        )
    }

    func fetchProtectedResourceMetadata(origin: URL, serverURL: URL) -> MCPProtectedResourceMetadata? {
        // Try the resource-scoped path first (RFC 9728 allows a path suffix), then the origin root.
        let candidates = Self.wellKnownCandidates(
            origin: origin,
            serverURL: serverURL,
            suffix: "oauth-protected-resource"
        )
        for url in candidates {
            if let metadata: MCPProtectedResourceMetadata = fetchJSON(url) {
                return metadata
            }
        }
        return nil
    }

    func fetchAuthorizationServerMetadata(base: URL) -> MCPAuthorizationServerMetadata? {
        let origin = (try? Self.origin(of: base)) ?? base
        // RFC 8414 well-known paths, plus the OpenID Connect fallback some servers use.
        let paths = [
            "/.well-known/oauth-authorization-server",
            "/.well-known/openid-configuration"
        ]
        for path in paths {
            if let url = URL(string: path, relativeTo: origin)?.absoluteURL,
               let metadata: MCPAuthorizationServerMetadata = fetchJSON(url) {
                return metadata
            }
        }
        return nil
    }
}
