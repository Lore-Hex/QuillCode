import XCTest
@testable import QuillCodeApp

/// Covers the secret shapes a run/HTTP error commonly leaks, exercised through the public
/// `diagnostic(from:)` path (WorkspaceContextSummarySecrets itself is private). These now feed
/// DURABLE, persisted run-failure notices, so a miss writes a secret to disk + the Activity stream.
final class WorkspaceContextSummarySecretRedactionTests: XCTestCase {
    private func redact(_ text: String) -> String {
        WorkspaceContextSummarySanitizer.diagnostic(from: text)
    }

    func testRedactsAuthorizationBearerTokenButKeepsTheWord() {
        for header in ["Authorization: Bearer sk8sJ2ndU_secretTokenValue123", "bearer AbC123dEf456ghI789"] {
            let out = redact("\(header) rejected")
            XCTAssertFalse(out.contains("secretTokenValue123"), out)
            XCTAssertFalse(out.contains("AbC123dEf456ghI789"), out)
            XCTAssertTrue(out.lowercased().contains("bearer [redacted]"), out)
        }
    }

    func testRedactsBareJWT() {
        // Assembled from segments so the committed source never contains a full JWT literal (which
        // trips GitHub push protection) — the runtime string is still a real three-segment JWT.
        let jwt = ["eyJhbGciOiJIUzI1NiJ9", "eyJzdWIiOiIxMjM0NTY3ODkwIn0", "dozjgNryP4J3jVmNHl0w5N"].joined(separator: ".")
        let out = redact("decode failed for \(jwt) at gateway")
        XCTAssertFalse(out.contains("eyJ"), out)
        XCTAssertTrue(out.contains("[redacted]"), out)
        XCTAssertTrue(out.contains("decode failed for"), "non-secret context is kept")
    }

    func testRedactsURLEmbeddedCredentialsKeepingSchemeAndHost() {
        let out = redact("connect https://alice:hunter2secret@db.internal.example/v1 failed")
        XCTAssertFalse(out.contains("alice"), out)
        XCTAssertFalse(out.contains("hunter2secret"), out)
        XCTAssertTrue(out.contains("https://[redacted]@db.internal.example/v1"), out)
    }

    func testRedactsURLPasswordContainingASlash() {
        // Unencoded connection-string passwords routinely contain "/"; the redactor must still reach
        // the "@" that ends the userinfo instead of leaking the password fragment.
        let out = redact("redis://cacheuser:p/w+ratio/2@redis.internal:6379 refused")
        XCTAssertFalse(out.contains("p/w+ratio/2"), out)
        XCTAssertTrue(out.contains("redis://[redacted]@redis.internal:6379"), out)
    }

    func testDoesNotRedactAHostPortWithNoCredentials() {
        // No user:pass@, so the URL rule must leave a plain host:port/path untouched.
        let benign = "listening on https://service.internal:8080/health"
        XCTAssertEqual(redact(benign), benign)
    }

    func testRedactsProviderPrefixedTokens() {
        // Each is assembled from a prefix + body so the committed source never holds a complete
        // provider-token literal (GitHub push protection blocks those), while the runtime string that
        // the redactor sees is byte-identical to a real token.
        let body = "0123456789abcdefABCDEF0123456789xyzQ"
        let cases = [
            "ghp_" + body,                          // GitHub personal
            "gho_" + body,                          // GitHub OAuth
            "github" + "_pat_" + body + "1122334455", // GitHub fine-grained PAT (current default)
            "AKIA" + "ABCDEFGHIJ012345",            // AWS access key id (long-term)
            "ASIA" + "ABCDEFGHIJ012345",            // AWS temp STS key
            "xoxb" + "-1234567890-abcdefABCDEF0987", // Slack bot
            "xoxe" + "-1234567890-abcdefABCDEF0987", // Slack refresh
            "xapp" + "-1-A0123456789-abcdefABCDEF"   // Slack app-level (socket mode)
        ]
        for secret in cases {
            let out = redact("provider error with \(secret) here")
            XCTAssertFalse(out.contains(secret), "\(secret) leaked: \(out)")
            XCTAssertTrue(out.contains("[redacted]"), out)
        }
    }

    func testRedactsGenericKeyValueSecretsKeepingTheKey() {
        for pair in ["password=hunter2secret", "token=abc123DEFvalue", "api_key=SYNTHETIC_LEAK_VALUE", "access-token=zzz999"] {
            let key = String(pair.prefix(upTo: pair.firstIndex(of: "=")!))
            let value = String(pair.suffix(from: pair.index(after: pair.firstIndex(of: "=")!)))
            let out = redact("request https://api.example/x?\(pair)&ok=1")
            XCTAssertFalse(out.contains(value), "\(pair) value leaked: \(out)")
            XCTAssertTrue(out.contains("\(key)=[redacted]"), out)
            XCTAssertTrue(out.contains("ok=1"), "a non-secret param is untouched: \(out)")
        }
    }

    func testKeepsRedactingTheOriginalSkKeysAndPrivateKeyBlocks() {
        XCTAssertFalse(redact("boom sk-tr-v1-abcdef123456ZZ done").contains("sk-tr-v1-abcdef123456ZZ"))
        let out = redact("-----BEGIN OPENSSH PRIVATE KEY----- blah")
        XCTAssertFalse(out.contains("PRIVATE KEY"), out)
        XCTAssertTrue(out.contains("[redacted]"), out)
    }

    func testDoesNotOverRedactOrdinaryDiagnostics() {
        for benign in [
            "Compacting context with TrustedRouter",
            "HTTP 500 server error while streaming the response",
            "the file token.swift could not be parsed at line 12"
        ] {
            XCTAssertEqual(redact(benign), benign, "no secret-shaped token here, so nothing should change")
        }
    }
}
