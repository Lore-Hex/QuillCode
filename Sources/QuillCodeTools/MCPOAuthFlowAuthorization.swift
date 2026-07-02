import Foundation

extension MCPOAuthFlow {
    // MARK: Authorization URL

    public func makeAuthorization(
        configuration: MCPOAuthConfiguration,
        clientID: String,
        redirectURI: String,
        scopes: [String] = [],
        challenge: MCPPKCEChallenge = .random(),
        state: String = MCPCrypto.randomToken(byteCount: 24)
    ) throws -> MCPOAuthAuthorization {
        guard URL(string: redirectURI) != nil else {
            throw MCPOAuthError.invalidRedirectURI(redirectURI)
        }
        guard var components = URLComponents(
            url: configuration.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw MCPOAuthError.invalidAuthorizationURL
        }
        var items = components.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: challenge.method),
            URLQueryItem(name: "state", value: state)
        ])
        let effectiveScopes = scopes.isEmpty ? configuration.scopesSupported : scopes
        if !effectiveScopes.isEmpty {
            items.append(URLQueryItem(name: "scope", value: effectiveScopes.joined(separator: " ")))
        }
        // RFC 8707 resource indicator — binds the token to this MCP resource.
        if let resource = configuration.resource, !resource.isEmpty {
            items.append(URLQueryItem(name: "resource", value: resource))
        }
        components.queryItems = items
        guard let url = components.url else {
            throw MCPOAuthError.invalidAuthorizationURL
        }
        return MCPOAuthAuthorization(
            authorizationURL: url,
            redirectURI: redirectURI,
            codeVerifier: challenge.codeVerifier,
            state: state,
            clientID: clientID
        )
    }

    // MARK: Callback

    /// Validate the redirect callback URL against the pending authorization's state and extract
    /// the authorization code. Rejects an `error=` callback and a mismatched/absent state.
    public func parseCallback(_ callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw MCPOAuthError.missingCode
        }
        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value
            throw MCPOAuthError.callbackError(description.map { "\(error): \($0)" } ?? error)
        }
        let state = items.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw MCPOAuthError.callbackStateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPOAuthError.missingCode
        }
        return code
    }
}
