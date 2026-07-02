import Foundation
import QuillCodeCore

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TrustedRouterOAuthError: Error, CustomStringConvertible {
    case invalidCallbackURL(String)
    case invalidAuthorizeURL
    case missingCallbackCode
    case callbackStateMismatch
    case exchangeFailed(statusCode: Int, body: String)
    case invalidExchangeResponse

    public var description: String {
        switch self {
        case .invalidCallbackURL(let value):
            return "Invalid TrustedRouter OAuth callback URL: \(value)"
        case .invalidAuthorizeURL:
            return "Could not construct TrustedRouter OAuth authorize URL."
        case .missingCallbackCode:
            return "TrustedRouter OAuth callback did not include a code."
        case .callbackStateMismatch:
            return "TrustedRouter OAuth callback state did not match the pending sign-in."
        case .exchangeFailed(let statusCode, let body):
            return "TrustedRouter OAuth exchange failed with HTTP \(statusCode): \(body)"
        case .invalidExchangeResponse:
            return "TrustedRouter OAuth exchange returned an invalid response."
        }
    }
}

public struct TrustedRouterPKCEChallenge: Sendable, Hashable {
    public var codeVerifier: String
    public var codeChallenge: String
    public var method: String

    public init(codeVerifier: String, method: String = "S256") {
        self.codeVerifier = codeVerifier
        self.codeChallenge = Self.s256Challenge(for: codeVerifier)
        self.method = method
    }

    public static func random(byteCount: Int = 32) -> TrustedRouterPKCEChallenge {
        var bytes = [UInt8]()
        bytes.reserveCapacity(byteCount)
        for _ in 0..<byteCount {
            bytes.append(UInt8.random(in: 0...255))
        }
        let verifier = base64URLEncoded(Data(bytes))
        return TrustedRouterPKCEChallenge(codeVerifier: verifier)
    }

    public static func s256Challenge(for verifier: String) -> String {
        base64URLEncoded(Data(sha256(Array(verifier.utf8))))
    }

    public static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256(_ message: [UInt8]) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(SHA256.hash(data: Data(message)))
        #else
        return SHA256Pure.digest(message)
        #endif
    }
}

public struct TrustedRouterOAuthAuthorization: Sendable, Hashable {
    public var url: URL
    public var callbackURL: URL
    public var codeVerifier: String
    public var state: String

    public init(url: URL, callbackURL: URL, codeVerifier: String, state: String) {
        self.url = url
        self.callbackURL = callbackURL
        self.codeVerifier = codeVerifier
        self.state = state
    }
}

public struct TrustedRouterOAuthToken: Codable, Sendable, Hashable {
    public var key: String
    public var userID: String?
    public var identity: Identity?

    public struct Identity: Codable, Sendable, Hashable {
        public var sub: String?
        public var email: String?
        public var emailVerified: Bool?
        public var walletAddress: String?

        enum CodingKeys: String, CodingKey {
            case sub, email
            case emailVerified = "email_verified"
            case walletAddress = "wallet_address"
        }
    }

    enum CodingKeys: String, CodingKey {
        case key, identity
        case userID = "user_id"
    }
}

public struct TrustedRouterUserInfo: Codable, Sendable, Hashable {
    public var data: TrustedRouterOAuthToken.Identity
}

public struct TrustedRouterOAuthClient: Sendable {
    public var baseURL: URL
    public var urlSession: URLSession

    public init(
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        urlSession: URLSession = .shared
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw TrustedRouterOAuthError.invalidAuthorizeURL
        }
        self.baseURL = url
        self.urlSession = urlSession
    }

    public func createAuthorization(
        callbackURL: String,
        keyLabel: String = "QuillCode",
        limit: String? = nil,
        usageLimitType: String? = nil,
        expiresAt: String? = nil,
        challenge: TrustedRouterPKCEChallenge = .random(),
        state: String = UUID().uuidString
    ) throws -> TrustedRouterOAuthAuthorization {
        guard var callbackComponents = URLComponents(string: callbackURL) else {
            throw TrustedRouterOAuthError.invalidCallbackURL(callbackURL)
        }
        var callbackQuery = callbackComponents.queryItems ?? []
        callbackQuery.append(URLQueryItem(name: "state", value: state))
        callbackComponents.queryItems = callbackQuery
        guard let callback = callbackComponents.url else {
            throw TrustedRouterOAuthError.invalidCallbackURL(callbackURL)
        }

        var components = URLComponents(url: baseURL.appendingPathComponent("auth"), resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "callback_url", value: callback.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: challenge.method),
            URLQueryItem(name: "key_label", value: keyLabel)
        ]
        if let limit {
            items.append(URLQueryItem(name: "limit", value: limit))
        }
        if let usageLimitType {
            items.append(URLQueryItem(name: "usage_limit_type", value: usageLimitType))
        }
        if let expiresAt {
            items.append(URLQueryItem(name: "expires_at", value: expiresAt))
        }
        components?.queryItems = items
        guard let url = components?.url else {
            throw TrustedRouterOAuthError.invalidAuthorizeURL
        }
        return TrustedRouterOAuthAuthorization(
            url: url,
            callbackURL: callback,
            codeVerifier: challenge.codeVerifier,
            state: state
        )
    }

    public func parseCallback(_ callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw TrustedRouterOAuthError.missingCallbackCode
        }
        let queryItems = components.queryItems ?? []
        let state = queryItems.first(where: { $0.name == "state" })?.value
        guard state == expectedState else {
            throw TrustedRouterOAuthError.callbackStateMismatch
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TrustedRouterOAuthError.missingCallbackCode
        }
        return code
    }

    public func exchangeCode(code: String, codeVerifier: String) async throws -> TrustedRouterOAuthToken {
        let url = baseURL.appendingPathComponent("auth/keys")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(ExchangeRequest(
            code: code,
            codeVerifier: codeVerifier,
            codeChallengeMethod: "S256"
        ))
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TrustedRouterOAuthError.exchangeFailed(
                statusCode: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
        let token = try JSONDecoder().decode(TrustedRouterOAuthToken.self, from: data)
        guard !token.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrustedRouterOAuthError.invalidExchangeResponse
        }
        return token
    }

    public func fetchUserInfo(apiKey: String) async throws -> TrustedRouterUserInfo {
        let url = baseURL.appendingPathComponent("auth/userinfo")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TrustedRouterOAuthError.exchangeFailed(
                statusCode: http.statusCode,
                body: String(decoding: data, as: UTF8.self)
            )
        }
        return try JSONDecoder().decode(TrustedRouterUserInfo.self, from: data)
    }

    private struct ExchangeRequest: Encodable {
        var code: String
        var codeVerifier: String
        var codeChallengeMethod: String

        enum CodingKeys: String, CodingKey {
            case code
            case codeVerifier = "code_verifier"
            case codeChallengeMethod = "code_challenge_method"
        }
    }
}
