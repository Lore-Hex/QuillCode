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
