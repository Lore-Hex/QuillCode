import Foundation

/// The result of RFC 7591 Dynamic Client Registration.
public struct MCPDynamicClientRegistration: Codable, Sendable, Hashable {
    public var clientID: String
    public var clientSecret: String?
    public var redirectURIs: [String]?

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case redirectURIs = "redirect_uris"
    }

    public init(
        clientID: String,
        clientSecret: String? = nil,
        redirectURIs: [String]? = nil
    ) {
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.redirectURIs = redirectURIs
    }
}
