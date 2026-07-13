import QuillCodeCore

enum WorkspaceSubagentTranscriptBuilder {
    private static let maxEntryCount = 24
    private static let maxDetailCharacters = 320

    static func entries(from thread: ChatThread) -> [SubagentTranscriptEntry] {
        let entries = WorkspaceTranscriptSurfaceBuilder(thread: thread).timelineItems().compactMap { item in
            switch item.kind {
            case .message:
                return item.message.flatMap(responseEntry)
            case .toolCard:
                return item.toolCard.map(toolEntry)
            }
        }
        return Array(entries.suffix(maxEntryCount))
    }

    private static func toolEntry(_ card: ToolCardState) -> SubagentTranscriptEntry {
        SubagentTranscriptEntry(
            id: "tool-\(card.id)",
            kind: card.status == .review ? .approval : .tool,
            title: WorkspaceToolDisplayNameBuilder.displayName(for: card.title),
            detail: boundedRedactedDetail(card.subtitle),
            statusLabel: card.statusDisplayLabel
        )
    }

    private static func responseEntry(_ message: MessageSurface) -> SubagentTranscriptEntry? {
        guard message.role == .assistant,
              let detail = WorkspaceContextSummarySanitizer.summary(from: message.text),
              !detail.isEmpty
        else {
            return nil
        }
        return SubagentTranscriptEntry(
            id: "message-\(message.id.uuidString)",
            kind: .assistant,
            title: "Response",
            detail: boundedRedactedDetail(detail),
            statusLabel: "Answered"
        )
    }

    private static func boundedRedactedDetail(_ text: String) -> String {
        let redacted = WorkspaceContextSummarySanitizer.summary(from: text) ?? ""
        let normalized = WorkspaceContextSummaryTextBounds.collapsedSingleLine(redacted)
        guard normalized.count > maxDetailCharacters else { return normalized }
        return WorkspaceContextSummaryTextBounds.prefix(normalized, limit: maxDetailCharacters)
    }
}
