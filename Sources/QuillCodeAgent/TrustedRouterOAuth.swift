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

#if !canImport(CryptoKit)
private enum SHA256Pure {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    static func digest(_ message: [UInt8]) -> [UInt8] {
        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
        ]
        var padded = message
        let bitLength = UInt64(message.count) * 8
        padded.append(0x80)
        while padded.count % 64 != 56 {
            padded.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            padded.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        func rotateRight(_ value: UInt32, _ count: UInt32) -> UInt32 {
            (value >> count) | (value << (32 - count))
        }

        for chunkStart in stride(from: 0, to: padded.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let byteIndex = chunkStart + index * 4
                words[index] = (UInt32(padded[byteIndex]) << 24)
                    | (UInt32(padded[byteIndex + 1]) << 16)
                    | (UInt32(padded[byteIndex + 2]) << 8)
                    | UInt32(padded[byteIndex + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], 7) ^ rotateRight(words[index - 15], 18) ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], 17) ^ rotateRight(words[index - 2], 19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }

            var a = hash[0], b = hash[1], c = hash[2], d = hash[3]
            var e = hash[4], f = hash[5], g = hash[6], h = hash[7]

            for index in 0..<64 {
                let s1 = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25)
                let choose = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choose &+ k[index] &+ words[index]
                let s0 = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }

            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }

        var output: [UInt8] = []
        output.reserveCapacity(32)
        for value in hash {
            output.append(UInt8((value >> 24) & 0xff))
            output.append(UInt8((value >> 16) & 0xff))
            output.append(UInt8((value >> 8) & 0xff))
            output.append(UInt8(value & 0xff))
        }
        return output
    }
}
#endif

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
