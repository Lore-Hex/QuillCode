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
    private static let secretPatterns = [
        #"sk-[A-Za-z0-9_-]{12,}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#
    ]

    static func redacted(_ text: String) -> String {
        secretPatterns.reduce(text) { result, pattern in
            result.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
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
