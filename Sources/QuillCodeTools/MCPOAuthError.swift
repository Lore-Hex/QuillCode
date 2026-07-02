import Foundation

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
            return "The MCP authorization server does not offer dynamic client registration "
                + "and no client ID was configured."
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
