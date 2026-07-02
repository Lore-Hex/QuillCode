import Foundation

/// A persisted OAuth token set for one remote MCP server. Stored as JSON in the secret store.
public struct MCPOAuthTokens: Codable, Sendable, Hashable {
    public var accessToken: String
    public var tokenType: String
    public var refreshToken: String?
    /// Absolute expiry, computed from `expires_in` at issuance. Nil means "no known expiry".
    public var expiresAt: Date?
    public var scope: String?

    public init(
        accessToken: String,
        tokenType: String = "Bearer",
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// The `Authorization` header value, e.g. `Bearer abc`. Normalizes the token type so a
    /// server that returns `"bearer"` still yields the canonical `Bearer` prefix.
    public var authorizationHeaderValue: String {
        let type = tokenType.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonical = type.lowercased() == "bearer" || type.isEmpty ? "Bearer" : type
        return "\(canonical) \(accessToken)"
    }

    /// True when the access token is at or past expiry (with a small safety skew).
    public func isExpired(now: Date = Date(), skew: TimeInterval = 30) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(skew) >= expiresAt
    }
}

/// Minimal key→value string persistence for MCP OAuth tokens and dynamic-registration client
/// credentials. Mirrors `QuillCodePersistence.QuillSecretStore` (which `QuillCodeTools` cannot
/// import) so the wiring layer can adapt its `FileSecretStore` to this protocol.
public protocol MCPSecretStore: Sendable {
    func read(_ key: String) throws -> String?
    func write(_ value: String, for key: String) throws
    func delete(_ key: String) throws
}

/// Namespaced secret keys for a remote MCP server, derived from its stable server ID.
public enum MCPSecretKeys {
    /// Sanitizes a server ID into a filename-safe secret key component.
    private static func safe(_ serverID: String) -> String {
        let mapped = serverID.unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_":
                return Character(scalar)
            default:
                return "_"
            }
        }
        let joined = String(mapped)
        return joined.isEmpty ? "server" : joined
    }

    public static func tokens(serverID: String) -> String {
        "mcp.\(safe(serverID)).oauth_tokens"
    }

    public static func clientRegistration(serverID: String) -> String {
        "mcp.\(safe(serverID)).oauth_client"
    }
}

/// A `MCPSecretStore`-backed reader/writer for a single server's tokens. Never logs token values.
public struct MCPTokenStore: Sendable {
    public let serverID: String
    private let secretStore: any MCPSecretStore

    public init(serverID: String, secretStore: any MCPSecretStore) {
        self.serverID = serverID
        self.secretStore = secretStore
    }

    public func loadTokens() -> MCPOAuthTokens? {
        guard let raw = try? secretStore.read(MCPSecretKeys.tokens(serverID: serverID)),
              let data = raw.data(using: .utf8),
              let tokens = try? JSONDecoder.mcpDateAware.decode(MCPOAuthTokens.self, from: data)
        else {
            return nil
        }
        return tokens
    }

    public func saveTokens(_ tokens: MCPOAuthTokens) throws {
        let data = try JSONEncoder.mcpDateAware.encode(tokens)
        guard let raw = String(data: data, encoding: .utf8) else { return }
        try secretStore.write(raw, for: MCPSecretKeys.tokens(serverID: serverID))
    }

    public func clearTokens() throws {
        try secretStore.delete(MCPSecretKeys.tokens(serverID: serverID))
    }

    public func loadClientRegistration() -> MCPDynamicClientRegistration? {
        guard let raw = try? secretStore.read(MCPSecretKeys.clientRegistration(serverID: serverID)),
              let data = raw.data(using: .utf8),
              let reg = try? JSONDecoder().decode(MCPDynamicClientRegistration.self, from: data)
        else {
            return nil
        }
        return reg
    }

    public func saveClientRegistration(_ registration: MCPDynamicClientRegistration) throws {
        let data = try JSONEncoder().encode(registration)
        guard let raw = String(data: data, encoding: .utf8) else { return }
        try secretStore.write(raw, for: MCPSecretKeys.clientRegistration(serverID: serverID))
    }
}

extension JSONDecoder {
    static var mcpDateAware: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

extension JSONEncoder {
    static var mcpDateAware: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}
