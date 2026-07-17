import CoreFoundation
import Foundation
import QuillCodeTools

struct AppServerWebSocketAuthError: Error, LocalizedError, Sendable, Equatable {
    let statusCode: Int
    let reason: String

    var errorDescription: String? { reason }

    static func unauthorized(_ reason: String) -> AppServerWebSocketAuthError {
        AppServerWebSocketAuthError(statusCode: 401, reason: reason)
    }
}

struct AppServerWebSocketAuthPolicy: Sendable {
    private static let defaultClockSkewSeconds: Int64 = 30
    private static let minimumSignedSecretBytes = 32
    private static let maximumSecretFileBytes = 64 * 1_024

    enum Mode: Sendable {
        case capabilityToken(digest: [UInt8])
        case signedBearerToken(
            secret: [UInt8],
            issuer: String?,
            audience: String?,
            clockSkewSeconds: Int64
        )
    }

    let mode: Mode?

    init(configuration: CLIAppServerWebSocketAuth) throws {
        switch configuration.mode {
        case .capabilityToken:
            if let path = configuration.tokenFile {
                let token = try Self.readSecret(path: path)
                mode = .capabilityToken(digest: MCPCrypto.sha256(Array(token.utf8)))
            } else if let hex = configuration.tokenSHA256 {
                mode = .capabilityToken(digest: try Self.decodeSHA256(hex))
            } else {
                throw CLIError.invalidAppServerAuth("capability token source is missing")
            }
        case .signedBearerToken:
            guard let path = configuration.sharedSecretFile else {
                throw CLIError.invalidAppServerAuth("signed bearer secret is missing")
            }
            let secret = Array(try Self.readSecret(path: path).utf8)
            guard secret.count >= Self.minimumSignedSecretBytes else {
                throw CLIError.invalidAppServerAuth(
                    "--ws-shared-secret-file must contain at least \(Self.minimumSignedSecretBytes) bytes"
                )
            }
            let skew = configuration.maxClockSkewSeconds ?? UInt64(Self.defaultClockSkewSeconds)
            guard skew <= UInt64(Int64.max) else {
                throw CLIError.invalidAppServerAuth("clock skew must fit in a signed 64-bit integer")
            }
            mode = .signedBearerToken(
                secret: secret,
                issuer: Self.normalized(configuration.issuer),
                audience: Self.normalized(configuration.audience),
                clockSkewSeconds: Int64(skew)
            )
        case nil:
            mode = nil
        }
    }

    var requiresAuthentication: Bool { mode != nil }

    func authorize(_ request: AppServerHTTPRequest, now: Date = Date()) throws {
        guard let mode else { return }
        guard let authorization = request.header("authorization"),
              let separator = authorization.firstIndex(of: " ")
        else {
            throw AppServerWebSocketAuthError.unauthorized("missing websocket bearer token")
        }
        let scheme = authorization[..<separator]
        let token = authorization[authorization.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
        guard scheme.caseInsensitiveCompare("Bearer") == .orderedSame, !token.isEmpty else {
            throw AppServerWebSocketAuthError.unauthorized("invalid authorization header")
        }

        switch mode {
        case .capabilityToken(let expectedDigest):
            let actualDigest = MCPCrypto.sha256(Array(token.utf8))
            guard Self.constantTimeEqual(expectedDigest, actualDigest) else {
                throw AppServerWebSocketAuthError.unauthorized("invalid websocket bearer token")
            }
        case .signedBearerToken(let secret, let issuer, let audience, let skew):
            try Self.verifyJWT(
                token,
                secret: secret,
                issuer: issuer,
                audience: audience,
                clockSkewSeconds: skew,
                now: Int64(now.timeIntervalSince1970)
            )
        }
    }

    private static func verifyJWT(
        _ token: String,
        secret: [UInt8],
        issuer: String?,
        audience: String?,
        clockSkewSeconds: Int64,
        now: Int64
    ) throws {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3,
              let headerData = decodeBase64URL(String(segments[0])),
              let claimsData = decodeBase64URL(String(segments[1])),
              let signature = decodeBase64URL(String(segments[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "HS256",
              let claims = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any]
        else {
            throw AppServerWebSocketAuthError.unauthorized("invalid websocket jwt")
        }

        let signedBytes = Array("\(segments[0]).\(segments[1])".utf8)
        let expectedSignature = hmacSHA256(key: secret, message: signedBytes)
        guard constantTimeEqual(expectedSignature, Array(signature)) else {
            throw AppServerWebSocketAuthError.unauthorized("invalid websocket jwt")
        }
        guard let expiration = integerClaim(claims["exp"]) else {
            throw AppServerWebSocketAuthError.unauthorized("invalid websocket jwt")
        }
        if now > expiration.saturatingAdd(clockSkewSeconds) {
            throw AppServerWebSocketAuthError.unauthorized("expired websocket jwt")
        }
        if let notBeforeValue = claims["nbf"] {
            guard let notBefore = integerClaim(notBeforeValue) else {
                throw AppServerWebSocketAuthError.unauthorized("invalid websocket jwt")
            }
            if now < notBefore.saturatingSubtract(clockSkewSeconds) {
                throw AppServerWebSocketAuthError.unauthorized("websocket jwt is not valid yet")
            }
        }
        if let issuer, claims["iss"] as? String != issuer {
            throw AppServerWebSocketAuthError.unauthorized("websocket jwt issuer mismatch")
        }
        if let audience, !audienceMatches(claims["aud"], expected: audience) {
            throw AppServerWebSocketAuthError.unauthorized("websocket jwt audience mismatch")
        }
    }

    private static func integerClaim(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        let doubleValue = number.doubleValue
        guard doubleValue.isFinite,
              doubleValue.rounded(.towardZero) == doubleValue,
              doubleValue >= Double(Int64.min),
              doubleValue <= Double(Int64.max)
        else { return nil }
        return number.int64Value
    }

    private static func audienceMatches(_ value: Any?, expected: String) -> Bool {
        if let single = value as? String { return single == expected }
        if let multiple = value as? [String] { return multiple.contains(expected) }
        return false
    }

    private static func hmacSHA256(key: [UInt8], message: [UInt8]) -> [UInt8] {
        let blockSize = 64
        var normalizedKey = key.count > blockSize ? MCPCrypto.sha256(key) : key
        if normalizedKey.count < blockSize {
            normalizedKey.append(contentsOf: repeatElement(0, count: blockSize - normalizedKey.count))
        }
        let innerPad = normalizedKey.map { $0 ^ 0x36 }
        let outerPad = normalizedKey.map { $0 ^ 0x5C }
        return MCPCrypto.sha256(outerPad + MCPCrypto.sha256(innerPad + message))
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        guard value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            return nil
        }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64.append(String(repeating: "=", count: 4 - remainder)) }
        return Data(base64Encoded: base64)
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }

    private static func decodeSHA256(_ value: String) throws -> [UInt8] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64 else {
            throw CLIError.invalidAppServerAuth("SHA-256 digest must contain 64 hexadecimal characters")
        }
        var digest: [UInt8] = []
        digest.reserveCapacity(32)
        var index = trimmed.startIndex
        for _ in 0..<32 {
            let next = trimmed.index(index, offsetBy: 2)
            guard let byte = UInt8(trimmed[index..<next], radix: 16) else {
                throw CLIError.invalidAppServerAuth("SHA-256 digest must contain 64 hexadecimal characters")
            }
            digest.append(byte)
            index = next
        }
        return digest
    }

    private static func readSecret(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size <= maximumSecretFileBytes
        else {
            throw CLIError.invalidAppServerAuth("secret file must be a bounded regular file")
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let raw = String(data: data, encoding: .utf8) else {
            throw CLIError.invalidAppServerAuth("secret file must contain UTF-8 text")
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw CLIError.invalidAppServerAuth("secret file must not be empty")
        }
        return value
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private extension Int64 {
    func saturatingAdd(_ other: Int64) -> Int64 {
        let (result, overflow) = addingReportingOverflow(other)
        return overflow ? (other >= 0 ? .max : .min) : result
    }

    func saturatingSubtract(_ other: Int64) -> Int64 {
        let (result, overflow) = subtractingReportingOverflow(other)
        return overflow ? (other >= 0 ? .min : .max) : result
    }
}
