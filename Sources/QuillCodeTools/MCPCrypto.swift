import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

/// Cryptographic helpers for the MCP OAuth 2.1 flow: PKCE challenge generation, base64url
/// encoding, and cryptographically-random state/verifier bytes.
///
/// This mirrors the reusable primitives in `QuillCodeAgent.TrustedRouterPKCEChallenge`, but is
/// duplicated here because `QuillCodeTools` sits below `QuillCodeAgent` in the dependency graph
/// and cannot import it. Kept deliberately small and dependency-free so the remote MCP
/// transport (which also lives in `QuillCodeTools`) can build a compliant auth request without
/// reaching up the module stack.
public enum MCPCrypto {
    /// base64url encoding without padding (RFC 7636 §4.1 / RFC 4648 §5).
    public static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Cryptographically secure random bytes. Uses the platform CSPRNG on Apple platforms and
    /// `SystemRandomNumberGenerator` (which is backed by the OS CSPRNG) elsewhere, so this is
    /// safe for OAuth state and PKCE verifiers on both macOS and Linux.
    public static func randomBytes(count: Int) -> Data {
        let count = max(0, count)
        // `UInt8.random(in:)` without an explicit generator draws from the OS CSPRNG
        // (`SystemRandomNumberGenerator`), which is what we want for OAuth state and PKCE
        // verifiers. A fresh generator per call is unnecessary; the default form is thread-safe.
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for _ in 0..<count {
            bytes.append(UInt8.random(in: 0...255))
        }
        return Data(bytes)
    }

    /// A base64url-encoded random token suitable for an OAuth `state` value or PKCE verifier.
    public static func randomToken(byteCount: Int = 32) -> String {
        base64URLEncoded(randomBytes(count: byteCount))
    }

    /// SHA-256 digest, using CryptoKit when available and a pure-Swift fallback on Linux.
    public static func sha256(_ message: [UInt8]) -> [UInt8] {
        #if canImport(CryptoKit)
        return Array(SHA256.hash(data: Data(message)))
        #else
        return MCPSHA256Pure.digest(message)
        #endif
    }

    /// The RFC 7636 S256 code challenge for a given code verifier.
    public static func s256Challenge(for verifier: String) -> String {
        base64URLEncoded(Data(sha256(Array(verifier.utf8))))
    }
}

/// A PKCE (RFC 7636) code verifier + S256 challenge pair.
public struct MCPPKCEChallenge: Sendable, Hashable {
    public var codeVerifier: String
    public var codeChallenge: String
    public var method: String

    public init(codeVerifier: String, method: String = "S256") {
        self.codeVerifier = codeVerifier
        self.codeChallenge = MCPCrypto.s256Challenge(for: codeVerifier)
        self.method = method
    }

    /// A fresh challenge with a random verifier. RFC 7636 requires 43–128 characters; 32 random
    /// bytes base64url-encode to 43 characters, the minimum.
    public static func random(byteCount: Int = 32) -> MCPPKCEChallenge {
        MCPPKCEChallenge(codeVerifier: MCPCrypto.randomToken(byteCount: max(32, byteCount)))
    }
}
