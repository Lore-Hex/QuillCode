import Foundation

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
