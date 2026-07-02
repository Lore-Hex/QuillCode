import Foundation

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
}
