import Foundation

/// Supplies (and refreshes) the bearer token for a remote MCP session. The transport stays
/// oblivious to how tokens are obtained: an unauthenticated server uses `MCPNoAuthorization`,
/// while an OAuth server uses a store-backed provider. Kept synchronous to match the transport's
/// blocking call style (the runtime invokes sessions on a background dispatch, like stdio).
public protocol MCPRemoteAuthorizing: Sendable {
    /// The current `Authorization` header value, or nil when the server needs no auth. May
    /// trigger a proactive refresh if the cached token is known to be expired.
    func currentAuthorizationHeader() -> String?

    /// Called after a 401. Attempts to refresh the token and returns the new header, or nil if
    /// refresh is impossible (no refresh token, refresh failed). Returning nil means the caller
    /// must surface an auth error rather than retry — there is no infinite loop.
    func refreshAuthorizationHeader() -> String?
}

/// No-auth provider for open MCP servers.
public struct MCPNoAuthorization: MCPRemoteAuthorizing {
    public init() {}
    public func currentAuthorizationHeader() -> String? { nil }
    public func refreshAuthorizationHeader() -> String? { nil }
}

/// A static bearer token (e.g. a pre-provisioned PAT) with no refresh capability.
public struct MCPStaticAuthorization: MCPRemoteAuthorizing {
    private let header: String

    public init(bearerToken: String) {
        self.header = "Bearer \(bearerToken)"
    }

    public func currentAuthorizationHeader() -> String? { header }
    public func refreshAuthorizationHeader() -> String? { nil }
}

/// Token-store-backed provider that refreshes via `MCPOAuthFlow` on demand. Thread-safe: the
/// cached tokens are guarded by a lock so concurrent tool calls share one refresh. Never logs
/// token material.
public final class MCPStoredOAuthAuthorization: MCPRemoteAuthorizing, @unchecked Sendable {
    private let flow: MCPOAuthFlow
    private let configuration: MCPOAuthConfiguration
    private let clientID: String
    private let tokenStore: MCPTokenStore
    private let lock = NSLock()
    private var tokens: MCPOAuthTokens?

    public init(
        flow: MCPOAuthFlow,
        configuration: MCPOAuthConfiguration,
        clientID: String,
        tokenStore: MCPTokenStore,
        initialTokens: MCPOAuthTokens? = nil
    ) {
        self.flow = flow
        self.configuration = configuration
        self.clientID = clientID
        self.tokenStore = tokenStore
        self.tokens = initialTokens ?? tokenStore.loadTokens()
    }

    public func currentAuthorizationHeader() -> String? {
        lock.lock()
        let current = tokens
        lock.unlock()
        guard let current else { return nil }
        if current.isExpired(), current.refreshToken != nil {
            return refreshAuthorizationHeader()
        }
        return current.authorizationHeaderValue
    }

    public func refreshAuthorizationHeader() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let refreshToken = tokens?.refreshToken else {
            return nil
        }
        do {
            let refreshed = try flow.refresh(
                configuration: configuration,
                clientID: clientID,
                refreshToken: refreshToken,
                scopes: configuration.scopesSupported
            )
            tokens = refreshed
            try? tokenStore.saveTokens(refreshed)
            return refreshed.authorizationHeaderValue
        } catch {
            return nil
        }
    }
}
