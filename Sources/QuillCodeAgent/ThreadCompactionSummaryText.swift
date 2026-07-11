import Foundation
import QuillCodeCore

/// Prompt construction, output sanitization, and the deterministic fallback for compaction summaries.
/// A small agent-layer sibling of the app's `WorkspaceContextSummaryPromptBuilder` /
/// `WorkspaceContextSummarySanitizer` — duplicated deliberately (not imported) because the app target
/// depends on the agent target, and the run-loop compaction that resumes a run must live down here.
enum ThreadCompactionSummaryText {
    // MARK: - Prompt

    /// The lowercased error/transcript scan window is bounded so a chatty tool result cannot blow the
    /// summary call's own context (the very problem we are fixing). Older + recent transcript combined
    /// is capped, keeping the TAIL (the most recent, most relevant turns) when it overflows.
    static let maxTranscriptCharacters = 18_000
    static let maxMessageExcerptCharacters = 1_200

    static func prompt(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) -> String {
        let transcript = boundedTranscript(olderMessages: olderMessages, recentMessages: recentMessages)
        return """
        Please compact this QuillCode coding-agent thread so the run can continue within its context window.

        Return exactly one QuillCode action JSON object and no markdown:
        {"type":"say","text":"..."}

        The text must be a concise durable continuation summary for the coding agent. Include:
        - the user's goal and explicit preferences
        - current implementation state and what has already been done
        - important files, commands, tests, branches, PRs, and decisions
        - unresolved questions, blockers, and the next steps

        Do not include tool-feedback JSON, credentials, API keys, private keys, or secrets. Do not invent completed work.

        Source thread: \(sourceTitle)

        Conversation to summarize:
        \(transcript)
        """
    }

    private static func boundedTranscript(
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) -> String {
        let joined = (olderMessages + recentMessages)
            .map { "- \(roleLabel($0.role)): \(summaryContent(for: $0, limit: maxMessageExcerptCharacters))" }
            .joined(separator: "\n")
        guard joined.count > maxTranscriptCharacters else { return joined }
        return String(joined.suffix(maxTranscriptCharacters))
    }

    // MARK: - Sanitize model output

    static let maxSummaryCharacters = 6_000

    /// Trims, redacts obvious secrets, and bounds the model's summary; nil when it is empty after
    /// trimming so the caller can fall back to the deterministic summary.
    static func sanitized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let redacted = redactSecrets(trimmed)
        guard redacted.count > maxSummaryCharacters else { return redacted }
        return String(redacted.prefix(maxSummaryCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    // MARK: - Deterministic fallback

    static let maxDeterministicExcerptCharacters = 180
    static let maxDeterministicOlderLines = 8

    /// A model-free summary of the dropped turns. Never empty (it always names the source and counts),
    /// so compaction can always proceed even with no summary model and no model output.
    static func deterministic(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) -> String {
        var lines = [
            "Context compacted from \"\(sourceTitle)\".",
            countLine(olderCount: olderMessages.count, recentCount: recentMessages.count),
        ]
        if olderMessages.isEmpty {
            lines.append("No earlier turns were dropped.")
        } else {
            lines.append("Earlier context:")
            for message in olderMessages.suffix(maxDeterministicOlderLines) {
                lines.append(
                    "- \(roleLabel(message.role)): "
                        + summaryContent(for: message, limit: maxDeterministicExcerptCharacters)
                )
            }
        }
        lines.append("Continue from the preserved latest turns below.")
        return redactSecrets(lines.joined(separator: "\n"))
    }

    private static func countLine(olderCount: Int, recentCount: Int) -> String {
        "Summarized \(pluralized(olderCount, noun: "earlier message")) and kept "
            + "\(pluralized(recentCount, noun: "recent message"))."
    }

    // MARK: - Shared helpers

    private static func roleLabel(_ role: ChatRole) -> String {
        switch role {
        case .system: return "System"
        case .user: return "User"
        case .assistant: return "Assistant"
        case .tool: return "Tool"
        }
    }

    /// Collapse whitespace and bound length. Uses `prefix` (never a range subscript) so an empty or
    /// multi-byte string can never trap.
    private static func excerpt(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func summaryContent(for message: ChatMessage, limit: Int) -> String {
        let imageSummary = message.attachments.isEmpty
            ? ""
            : "[Attached images: \(message.attachments.map(\.displayName).joined(separator: ", "))]"
        return [excerpt(message.content, limit: limit), imageSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func pluralized(_ count: Int, noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private static let secretPatterns = [
        #"sk-[A-Za-z0-9_-]{12,}"#,
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#,
    ]

    private static func redactSecrets(_ text: String) -> String {
        secretPatterns.reduce(text) { result, pattern in
            result.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
    }
}
