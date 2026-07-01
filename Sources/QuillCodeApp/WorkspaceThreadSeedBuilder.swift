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

    static func forkSeedMessages(
        from thread: ChatThread,
        strategy: WorkspaceThreadForkStrategy,
        summaryOverride: String? = nil
    ) -> [ChatMessage] {
        switch strategy {
        case .latestTurn:
            forkSeedMessages(from: thread.messages)
        case .summarizedContext:
            summarizedForkSeedMessages(from: thread, summaryOverride: summaryOverride)
        case .fullContext:
            fullContextSeedMessages(from: thread.messages)
        }
    }

    static func summarizedForkSeedMessages(
        from thread: ChatThread,
        summaryOverride: String? = nil
    ) -> [ChatMessage] {
        let context = summaryContext(from: thread)
        return [summaryMessage(
            sourceTitle: thread.title,
            olderMessages: context.olderMessages,
            recentMessages: context.recentMessages,
            purpose: .forkSummary,
            summaryOverride: summaryOverride
        )] + context.recentMessages
    }

    static func fullContextSeedMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        visibleConversationMessages(from: messages)
    }

    static func compactSeedMessages(
        from thread: ChatThread,
        summaryOverride: String? = nil
    ) -> [ChatMessage] {
        let context = summaryContext(from: thread)
        return [summaryMessage(
            sourceTitle: thread.title,
            olderMessages: context.olderMessages,
            recentMessages: context.recentMessages,
            purpose: .compact,
            summaryOverride: summaryOverride
        )] + context.recentMessages
    }

    static func summaryContext(from thread: ChatThread) -> WorkspaceContextSummaryContext {
        let visibleMessages = visibleConversationMessages(from: thread.messages)
        let recentMessages = forkSeedMessages(from: visibleMessages)
        let recentIDs = Set(recentMessages.map(\.id))
        let olderMessages = visibleMessages.filter { !recentIDs.contains($0.id) }
        return WorkspaceContextSummaryContext(
            olderMessages: olderMessages,
            recentMessages: recentMessages
        )
    }

    static func summaryText(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage],
        purpose: WorkspaceContextSummaryPurpose
    ) -> String {
        summaryMessage(
            sourceTitle: sourceTitle,
            olderMessages: olderMessages,
            recentMessages: recentMessages,
            purpose: SummaryPurpose(purpose)
        ).content
    }

    private static func visibleConversationMessages(from messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .tool }
    }

    private static func summaryMessage(
        sourceTitle: String,
        olderMessages: [ChatMessage],
        recentMessages: [ChatMessage],
        purpose: SummaryPurpose,
        summaryOverride: String? = nil
    ) -> ChatMessage {
        if let summaryOverride = summaryOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summaryOverride.isEmpty {
            return ChatMessage(role: .assistant, content: [
                purpose.titleLine(sourceTitle: sourceTitle),
                "Model summary:",
                summaryOverride,
                purpose.closingLine
            ].joined(separator: "\n"))
        }

        let olderCount = olderMessages.count
        let recentCount = recentMessages.count
        var lines = [
            purpose.titleLine(sourceTitle: sourceTitle),
            countSummary(recentCount: recentCount, olderCount: olderCount)
        ]
        if olderMessages.isEmpty {
            lines.append("No earlier turns were dropped.")
        } else {
            lines.append("Earlier context:")
            for message in olderMessages.suffix(6) {
                lines.append("- \(roleLabel(message.role)): \(singleLineExcerpt(message.content, limit: 180))")
            }
        }
        lines.append(purpose.closingLine)
        return ChatMessage(role: .assistant, content: lines.joined(separator: "\n"))
    }

    private enum SummaryPurpose {
        case compact
        case forkSummary

        init(_ purpose: WorkspaceContextSummaryPurpose) {
            switch purpose {
            case .compact:
                self = .compact
            case .forkSummary:
                self = .forkSummary
            }
        }

        func titleLine(sourceTitle: String) -> String {
            switch self {
            case .compact:
                "Context compacted from \"\(sourceTitle)\"."
            case .forkSummary:
                "Context forked from \"\(sourceTitle)\" with a summary."
            }
        }

        var closingLine: String {
            switch self {
            case .compact:
                "Continue from the preserved latest turn below."
            case .forkSummary:
                "Continue the fork from the preserved latest turn below."
            }
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

    private static func countSummary(recentCount: Int, olderCount: Int) -> String {
        "Kept \(pluralized(recentCount, noun: "latest message")) " +
            "and summarized \(pluralized(olderCount, noun: "earlier message"))."
    }

    private static func pluralized(_ count: Int, noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    private static func singleLineExcerpt(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
