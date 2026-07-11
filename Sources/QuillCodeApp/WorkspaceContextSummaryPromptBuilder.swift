import Foundation
import QuillCodeCore

enum WorkspaceContextSummaryPromptBuilder {
    private static let maxConversationCharacters = 18_000

    static func prompt(for request: WorkspaceContextSummaryRequest) -> String {
        let transcript = boundedTranscript(for: request)
        return """
        Please \(request.purpose.promptTitle).

        Return exactly one QuillCode action JSON object and no markdown:
        {"type":"say","text":"..."}

        The text must be a concise durable continuation summary for a coding agent. Include:
        - user goals and explicit preferences
        - current implementation state
        - important files, commands, tests, branches, PRs, and decisions
        - unresolved questions, blockers, and next steps

        Do not include tool-feedback JSON, credentials, API keys, private keys, or secrets. Do not invent completed work.

        Source thread: \(request.sourceTitle)

        Visible conversation:
        \(transcript)
        """
    }

    private static func boundedTranscript(for request: WorkspaceContextSummaryRequest) -> String {
        let joined = transcriptLines(for: request).joined(separator: "\n")
        guard joined.count > maxConversationCharacters else { return joined }
        return String(joined.suffix(maxConversationCharacters))
    }

    private static func transcriptLines(for request: WorkspaceContextSummaryRequest) -> [String] {
        (request.olderMessages + request.recentMessages).map { message in
            let imageSummary = message.attachments.isEmpty
                ? ""
                : "[Attached images: \(message.attachments.map(\.displayName).joined(separator: ", "))]"
            let content = [singleLine(message.content, limit: 1_200), imageSummary]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return "- \(roleLabel(message.role)): \(content)"
        }
    }

    private static func roleLabel(_ role: ChatRole) -> String {
        switch role {
        case .system:
            return "System"
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .tool:
            return "Tool"
        }
    }

    private static func singleLine(_ text: String, limit: Int) -> String {
        let collapsed = WorkspaceContextSummaryTextBounds.collapsedSingleLine(text)
        guard collapsed.count > limit else { return collapsed }
        return WorkspaceContextSummaryTextBounds.prefix(collapsed, limit: limit)
    }
}
