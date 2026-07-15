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
        if let staticClientID, !staticClientID.isEmpty {
            return MCPDynamicClientRegistration(
                clientID: staticClientID,
                redirectURIs: [redirectURI]
            )
        }
        if let existing {
            if existing.redirectURIs?.contains(redirectURI) == true {
                return existing
            }
            // Older persisted registrations did not record their redirect URI. Reuse them only
            // when the provider gives us no way to repair that legacy state. A known mismatch is
            // never reusable because the authorization server will reject the callback.
            if existing.redirectURIs == nil, configuration.registrationEndpoint == nil {
                return existing
            }
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
        guard var registration = try? JSONDecoder().decode(MCPDynamicClientRegistration.self, from: response.body),
              !registration.clientID.isEmpty else {
            throw MCPOAuthError.invalidTokenResponse
        }
        if registration.redirectURIs?.isEmpty != false {
            registration.redirectURIs = [redirectURI]
        }
        return registration
    }
}
