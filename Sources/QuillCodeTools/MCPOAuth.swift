import Foundation

// MARK: - Discovery metadata

/// OAuth 2.0 Protected Resource Metadata (RFC 9728) as served by an MCP server at
/// `/.well-known/oauth-protected-resource`. Points at the authorization server(s).
public struct MCPProtectedResourceMetadata: Decodable, Sendable, Hashable {
    public var resource: String?
    public var authorizationServers: [String]?
    public var scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
    }
}

/// OAuth 2.0 Authorization Server Metadata (RFC 8414). The subset the MCP flow needs.
public struct MCPAuthorizationServerMetadata: Decodable, Sendable, Hashable {
    public var issuer: String?
    public var authorizationEndpoint: String?
    public var tokenEndpoint: String?
    public var registrationEndpoint: String?
    public var scopesSupported: [String]?
    public var codeChallengeMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }
}

/// The result of RFC 7591 Dynamic Client Registration.
public struct MCPDynamicClientRegistration: Codable, Sendable, Hashable {
    public var clientID: String
    public var clientSecret: String?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }

    public init(clientID: String, clientSecret: String? = nil) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

/// The endpoints and client identity resolved for one server, ready to drive an auth-code flow.
public struct MCPOAuthConfiguration: Sendable, Hashable {
    public var authorizationEndpoint: URL
    public var tokenEndpoint: URL
    public var registrationEndpoint: URL?
    public var resource: String?
    public var scopesSupported: [String]

    public init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        registrationEndpoint: URL? = nil,
        resource: String? = nil,
        scopesSupported: [String] = []
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.registrationEndpoint = registrationEndpoint
        self.resource = resource
        self.scopesSupported = scopesSupported
    }
}

/// A pending authorization: the URL to open in a browser plus the PKCE verifier and state the
/// caller must retain to finish the exchange.
public struct MCPOAuthAuthorization: Sendable, Hashable {
    public var authorizationURL: URL
    public var redirectURI: String
    public var codeVerifier: String
    public var state: String
    public var clientID: String

    public init(authorizationURL: URL, redirectURI: String, codeVerifier: String, state: String, clientID: String) {
        self.authorizationURL = authorizationURL
        self.redirectURI = redirectURI
        self.codeVerifier = codeVerifier
        self.state = state
        self.clientID = clientID
    }
}

public enum MCPOAuthError: Error, Sendable, CustomStringConvertible, Equatable {
    case discoveryFailed(String)
    case noAuthorizationServer
    case missingEndpoint(String)
    case registrationFailed(statusCode: Int, body: String)
    case registrationUnavailable
    case invalidAuthorizationURL
    case invalidRedirectURI(String)
    case invalidServerURL(String)
    case callbackStateMismatch
    case callbackError(String)
    case missingCode
    case tokenExchangeFailed(statusCode: Int, body: String)
    case invalidTokenResponse
    case noRefreshToken

    public var description: String {
        switch self {
        case .discoveryFailed(let message):
            return "MCP OAuth discovery failed: \(message)"
        case .noAuthorizationServer:
            return "The MCP server did not advertise an OAuth authorization server."
        case .missingEndpoint(let name):
            return "The MCP authorization server metadata is missing its \(name)."
        case .registrationFailed(let statusCode, let body):
            return "MCP dynamic client registration failed with HTTP \(statusCode): \(body)"
        case .registrationUnavailable:
            return "The MCP authorization server does not offer dynamic client registration and no client ID was configured."
        case .invalidAuthorizationURL:
            return "Could not construct the MCP authorization URL."
        case .invalidRedirectURI(let value):
            return "Invalid MCP OAuth redirect URI: \(value)"
        case .invalidServerURL(let value):
            return "Invalid MCP server URL: \(value)"
        case .callbackStateMismatch:
            return "The MCP OAuth callback state did not match the pending sign-in."
        case .callbackError(let message):
            return "The MCP OAuth callback returned an error: \(message)"
        case .missingCode:
            return "The MCP OAuth callback did not include an authorization code."
        case .tokenExchangeFailed(let statusCode, let body):
            return "MCP OAuth token exchange failed with HTTP \(statusCode): \(body)"
        case .invalidTokenResponse:
            return "The MCP OAuth token response was invalid."
        case .noRefreshToken:
            return "No refresh token is available to renew the MCP session."
        }
    }
}

/// Drives the MCP OAuth 2.1 authorization-code + PKCE flow against a remote MCP server.
///
/// Flow (per the MCP authorization spec):
///  1. `discover(serverURL:)` — fetch protected-resource metadata, then authorization-server
///     metadata, to resolve the authorize/token/registration endpoints.
///  2. `registerClientIfNeeded(...)` — RFC 7591 dynamic registration when the server offers it
///     and no static client ID is configured. The result is persisted so we don't re-register.
///  3. `makeAuthorization(...)` — build the browser URL with PKCE `code_challenge`, a random
///     `state`, and the loopback `redirect_uri`.
///  4. `parseCallback(...)` — validate `state` and extract the code from the redirect.
///  5. `exchangeCode(...)` / `refresh(...)` — swap the code (or a refresh token) for tokens at
///     the token endpoint.
///
/// The struct itself performs no browser interaction and holds no server state, so it is fully
/// testable against a stubbed `MCPHTTPClient`.
public struct MCPOAuthFlow: Sendable {
    public var httpClient: any MCPHTTPClient
    public var clientName: String

    public init(httpClient: any MCPHTTPClient, clientName: String = "QuillCode") {
        self.httpClient = httpClient
        self.clientName = clientName
    }

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

    private func fetchProtectedResourceMetadata(origin: URL, serverURL: URL) -> MCPProtectedResourceMetadata? {
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

    private func fetchAuthorizationServerMetadata(base: URL) -> MCPAuthorizationServerMetadata? {
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

    // MARK: Dynamic client registration

    /// Register a client via RFC 7591 if the server offers a registration endpoint and no client
    /// ID is already known. Returns the client credentials to use for the flow.
    public func registerClientIfNeeded(
        configuration: MCPOAuthConfiguration,
        redirectURI: String,
        existing: MCPDynamicClientRegistration?,
        staticClientID: String?
    ) throws -> MCPDynamicClientRegistration {
        if let existing { return existing }
        if let staticClientID, !staticClientID.isEmpty {
            return MCPDynamicClientRegistration(clientID: staticClientID)
        }
        guard let registrationEndpoint = configuration.registrationEndpoint else {
            throw MCPOAuthError.registrationUnavailable
        }

        let payload: [String: Any] = [
            "client_name": clientName,
            "redirect_uris": [redirectURI],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let request = MCPHTTPRequest(
            url: registrationEndpoint,
            method: "POST",
            headers: ["Content-Type": "application/json", "Accept": "application/json"],
            body: body,
            timeout: 30
        )
        let response = try httpClient.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw MCPOAuthError.registrationFailed(
                statusCode: response.statusCode,
                body: Self.previewBody(response.body)
            )
        }
        guard let registration = try? JSONDecoder().decode(MCPDynamicClientRegistration.self, from: response.body),
              !registration.clientID.isEmpty else {
            throw MCPOAuthError.invalidTokenResponse
        }
        return registration
    }

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
        guard var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false) else {
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

    // MARK: Token exchange & refresh

    public func exchangeCode(
        configuration: MCPOAuthConfiguration,
        clientID: String,
        redirectURI: String,
        code: String,
        codeVerifier: String
    ) throws -> MCPOAuthTokens {
        var form: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier
        ]
        if let resource = configuration.resource, !resource.isEmpty {
            form["resource"] = resource
        }
        return try postToken(configuration: configuration, form: form)
    }

    public func refresh(
        configuration: MCPOAuthConfiguration,
        clientID: String,
        refreshToken: String,
        scopes: [String] = []
    ) throws -> MCPOAuthTokens {
        var form: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        if !scopes.isEmpty {
            form["scope"] = scopes.joined(separator: " ")
        }
        if let resource = configuration.resource, !resource.isEmpty {
            form["resource"] = resource
        }
        let tokens = try postToken(configuration: configuration, form: form)
        // A refresh response may omit the refresh token, meaning "keep using the old one".
        if tokens.refreshToken == nil {
            return MCPOAuthTokens(
                accessToken: tokens.accessToken,
                tokenType: tokens.tokenType,
                refreshToken: refreshToken,
                expiresAt: tokens.expiresAt,
                scope: tokens.scope
            )
        }
        return tokens
    }

    private func postToken(configuration: MCPOAuthConfiguration, form: [String: String]) throws -> MCPOAuthTokens {
        let body = Self.formURLEncoded(form)
        let request = MCPHTTPRequest(
            url: configuration.tokenEndpoint,
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ],
            body: Data(body.utf8),
            timeout: 30
        )
        let response = try httpClient.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw MCPOAuthError.tokenExchangeFailed(
                statusCode: response.statusCode,
                body: Self.previewBody(response.body)
            )
        }
        return try Self.decodeTokens(from: response.body)
    }

    // MARK: Helpers

    static func decodeTokens(from data: Data) throws -> MCPOAuthTokens {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw MCPOAuthError.invalidTokenResponse
        }
        guard let accessToken = (object["access_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !accessToken.isEmpty else {
            throw MCPOAuthError.invalidTokenResponse
        }
        let tokenType = (object["token_type"] as? String) ?? "Bearer"
        let refreshToken = (object["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = object["scope"] as? String
        var expiresAt: Date?
        if let expiresIn = Self.number(object["expires_in"]), expiresIn > 0 {
            expiresAt = Date().addingTimeInterval(expiresIn)
        }
        return MCPOAuthTokens(
            accessToken: accessToken,
            tokenType: tokenType,
            refreshToken: (refreshToken?.isEmpty == false) ? refreshToken : nil,
            expiresAt: expiresAt,
            scope: scope
        )
    }

    private static func number(_ value: Any?) -> TimeInterval? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return TimeInterval(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) }
        return nil
    }

    private func fetchJSON<T: Decodable>(_ url: URL) -> T? {
        let request = MCPHTTPRequest(
            url: url,
            method: "GET",
            headers: ["Accept": "application/json"],
            timeout: 15,
            maxResponseBytes: 512 * 1024
        )
        guard let response = try? httpClient.perform(request),
              (200..<300).contains(response.statusCode),
              !response.bodyExceededMaxBytes else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: response.body)
    }

    /// The scheme+host+port origin of a URL, validated for http/https and a real host.
    static func origin(of url: URL) throws -> URL {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            throw MCPOAuthError.invalidServerURL(url.absoluteString)
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = url.port
        guard let origin = components.url else {
            throw MCPOAuthError.invalidServerURL(url.absoluteString)
        }
        return origin
    }

    /// Candidate well-known URLs for protected-resource metadata: the resource-path variant
    /// (well-known segment inserted before the path) and the origin-root variant.
    static func wellKnownCandidates(origin: URL, serverURL: URL, suffix: String) -> [URL] {
        var urls: [URL] = []
        let path = serverURL.path
        if !path.isEmpty, path != "/" {
            if let scoped = URL(string: "/.well-known/\(suffix)\(path)", relativeTo: origin)?.absoluteURL {
                urls.append(scoped)
            }
        }
        if let root = URL(string: "/.well-known/\(suffix)", relativeTo: origin)?.absoluteURL {
            urls.append(root)
        }
        return urls
    }

    static func formURLEncoded(_ fields: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    /// A bounded, log-safe preview of an error body — never includes token material because
    /// error bodies are OAuth error JSON, and we cap length to avoid dumping huge pages.
    static func previewBody(_ data: Data, limit: Int = 512) -> String {
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
