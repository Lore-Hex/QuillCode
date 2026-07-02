import Foundation

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
