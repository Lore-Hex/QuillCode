import Foundation
import QuillCodeCore

struct WorkspaceThreadSeedBuilder: Sendable, Hashable {
    static func title(fromUserPrompt userPrompt: String) -> String {
        let words = userPrompt
            .split(whereSeparator: \.isWhitespace)
            .prefix(6)
            .joined(separator: " ")
        return words.isEmpty ? "New chat" : words
    }

    static func forkSeedMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        let visibleMessages = visibleConversationMessages(from: messages)
        guard let lastUserIndex = visibleMessages.lastIndex(where: { $0.role == .user }) else {
            return Array(visibleMessages.suffix(4))
        }
        return Array(visibleMessages[lastUserIndex...].prefix(4))
    }

    static func compactSeedMessages(from thread: ChatThread) -> [ChatMessage] {
        let visibleMessages = visibleConversationMessages(from: thread.messages)
        let recentMessages = forkSeedMessages(from: visibleMessages)
        let recentIDs = Set(recentMessages.map(\.id))
        let olderMessages = visibleMessages.filter { !recentIDs.contains($0.id) }
        return [compactSummaryMessage(
            sourceTitle: thread.title,
            olderMessages: olderMessages,
            recentMessages: recentMessages
        )] + recentMessages
    }

    private static func visibleConversationMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .tool }
    }

    private static func compactSummaryMessage(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage]
    ) -> ChatMessage {
        let olderCount = olderMessages.count
        let recentCount = recentMessages.count
        var lines = [
            "Context compacted from \"\(sourceTitle)\".",
            "Kept \(recentCount) latest message\(recentCount == 1 ? "" : "s") and summarized \(olderCount) earlier message\(olderCount == 1 ? "" : "s")."
        ]
        if olderMessages.isEmpty {
            lines.append("No earlier turns were dropped.")
        } else {
            lines.append("Earlier context:")
            for message in olderMessages.suffix(6) {
                lines.append("- \(roleLabel(message.role)): \(singleLineExcerpt(message.content, limit: 180))")
            }
        }
        lines.append("Continue from the preserved latest turn below.")
        return ChatMessage(role: .assistant, content: lines.joined(separator: "\n"))
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

    private static func singleLineExcerpt(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
