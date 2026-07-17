import Foundation

enum WorkspaceContextSummarySanitizer {
    private static let maxSummaryCharacters = 6_000
    private static let maxDiagnosticCharacters = 180

    static func summary(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let redacted = WorkspaceContextSummarySecrets.redacted(trimmed)
        guard redacted.count > maxSummaryCharacters else { return redacted }
        return WorkspaceContextSummaryTextBounds.prefix(redacted, limit: maxSummaryCharacters)
    }

    static func diagnostic(from text: String) -> String {
        let collapsed = WorkspaceContextSummaryTextBounds.collapsedSingleLine(text)
        let redacted = WorkspaceContextSummarySecrets.redacted(collapsed)
        guard redacted.count > maxDiagnosticCharacters else { return redacted }
        return WorkspaceContextSummaryTextBounds.prefix(redacted, limit: maxDiagnosticCharacters)
    }
}

private enum WorkspaceContextSummarySecrets {
    /// (regex, replacement) pairs applied in order. A replacement may reference capture groups (`$1`)
    /// to keep the NON-secret context — a URL's scheme+host, the "Bearer" word, a `token=` key — while
    /// dropping only the value, which is far more useful in a diagnostic than blanking the whole line.
    /// This runs on durable, persisted run-failure notices (WorkspaceRunFailureNoticePlanner) as well
    /// as context summaries, so the shapes below are the ones a run/HTTP error commonly leaks.
    /// Broadening only ever redacts MORE, which is always safe for a diagnostic.
    /// Case-sensitivity is per-pattern (inline `(?i)`): the fixed-prefix keys (sk-, ghp_, AKIA, xox,
    /// eyJ) are case-specific and must NOT be lowercased-matched, only "Bearer" and the key= names are.
    private static let redactionRules: [(pattern: String, replacement: String)] = [
        (#"-----BEGIN [A-Z ]*PRIVATE KEY-----"#, "[redacted]"),
        (#"sk-[A-Za-z0-9_-]{12,}"#, "[redacted]"),
        // URL-embedded credentials — keep the scheme and host, drop user:pass. The user is a simple
        // token (no slash), but the PASSWORD may contain "/" unencoded (redis:// / postgres:// dumps),
        // so it accepts anything up to the "@" that precedes the host.
        (#"([A-Za-z][A-Za-z0-9+.-]*://)[^\s:/@]+:[^\s@]+@"#, "$1[redacted]@"),
        // Authorization: Bearer <token> / a bare "Bearer <token>".
        (#"(?i)(bearer)\s+[A-Za-z0-9._~+/=-]{8,}"#, "$1 [redacted]"),
        // Bare JWTs: three base64url segments, header begins "eyJ".
        (#"eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#, "[redacted]"),
        // Provider tokens with recognizable prefixes.
        (#"gh[pousr]_[A-Za-z0-9]{20,}"#, "[redacted]"),      // GitHub personal/OAuth/user/server/refresh
        (#"github_pat_[A-Za-z0-9_]{22,}"#, "[redacted]"),    // GitHub fine-grained PAT (current default)
        (#"(?:AKIA|ASIA)[0-9A-Z]{16}"#, "[redacted]"),       // AWS access key id (long-term / temp STS)
        (#"(?:xox[baprse]|xapp)-[A-Za-z0-9-]{10,}"#, "[redacted]"), // Slack bot/user/app/refresh/legacy/socket
        // Generic key=value secrets in query strings / opaque params — keep the key, drop the value.
        (#"(?i)(password|passwd|pwd|token|api[_-]?key|apikey|secret|access[_-]?token)=[^\s&"']+"#, "$1=[redacted]")
    ]

    static func redacted(_ text: String) -> String {
        redactionRules.reduce(text) { result, rule in
            result.replacingOccurrences(
                of: rule.pattern,
                with: rule.replacement,
                options: .regularExpression
            )
        }
    }
}

enum WorkspaceContextSummaryTextBounds {
    static func collapsedSingleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func prefix(_ text: String, limit: Int) -> String {
        String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
