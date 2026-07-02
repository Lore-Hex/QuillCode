import Foundation

extension MCPOAuthFlow {
    // MARK: Token exchange & refresh

    public func exchangeCode(
        configuration: MCPOAuthConfiguration,
        clientID: String,
        redirectURI: String,
        code: String,
        codeVerifier: String
    ) throws -> MCPOAuthTokens {
        var form: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": codeVerifier
        ]
        if let resource = configuration.resource, !resource.isEmpty {
            form["resource"] = resource
        }
        return try postToken(configuration: configuration, form: form)
    }

    public func refresh(
        configuration: MCPOAuthConfiguration,
        clientID: String,
        refreshToken: String,
        scopes: [String] = []
    ) throws -> MCPOAuthTokens {
        var form: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        if !scopes.isEmpty {
            form["scope"] = scopes.joined(separator: " ")
        }
        if let resource = configuration.resource, !resource.isEmpty {
            form["resource"] = resource
        }
        let tokens = try postToken(configuration: configuration, form: form)
        // A refresh response may omit the refresh token, meaning "keep using the old one".
        if tokens.refreshToken == nil {
            return MCPOAuthTokens(
                accessToken: tokens.accessToken,
                tokenType: tokens.tokenType,
                refreshToken: refreshToken,
                expiresAt: tokens.expiresAt,
                scope: tokens.scope
            )
        }
        return tokens
    }

    func postToken(configuration: MCPOAuthConfiguration, form: [String: String]) throws -> MCPOAuthTokens {
        let body = Self.formURLEncoded(form)
        let request = MCPHTTPRequest(
            url: configuration.tokenEndpoint,
            method: "POST",
            headers: [
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json"
            ],
            body: Data(body.utf8),
            timeout: 30
        )
        let response = try httpClient.perform(request)
        guard (200..<300).contains(response.statusCode) else {
            throw MCPOAuthError.tokenExchangeFailed(
                statusCode: response.statusCode,
                body: Self.previewBody(response.body)
            )
        }
        return try Self.decodeTokens(from: response.body)
    }

    // MARK: Helpers

    static func decodeTokens(from data: Data) throws -> MCPOAuthTokens {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw MCPOAuthError.invalidTokenResponse
        }
        guard let accessToken = (object["access_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !accessToken.isEmpty else {
            throw MCPOAuthError.invalidTokenResponse
        }
        let tokenType = (object["token_type"] as? String) ?? "Bearer"
        let refreshToken = (object["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = object["scope"] as? String
        var expiresAt: Date?
        if let expiresIn = Self.number(object["expires_in"]), expiresIn > 0 {
            expiresAt = Date().addingTimeInterval(expiresIn)
        }
        return MCPOAuthTokens(
            accessToken: accessToken,
            tokenType: tokenType,
            refreshToken: (refreshToken?.isEmpty == false) ? refreshToken : nil,
            expiresAt: expiresAt,
            scope: scope
        )
    }

    static func number(_ value: Any?) -> TimeInterval? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return TimeInterval(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return TimeInterval(string) }
        return nil
    }
}
