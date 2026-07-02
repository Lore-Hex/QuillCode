import Foundation

extension MCPOAuthFlow {
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
}
