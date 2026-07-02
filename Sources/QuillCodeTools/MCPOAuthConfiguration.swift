import Foundation

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
