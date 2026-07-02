import QuillCodeCore

/// Renders the current thread transcript as Markdown for the clipboard ("Copy
/// conversation"). It walks the timeline in order, emitting a `## Role` heading + body for
/// each user/assistant message and a `### title` + fenced block for each tool run, reusing
/// ``TranscriptItemTextFormatter`` for tool-card text so the export matches the per-item
/// copy exactly. Returns `""` when there is nothing to copy.
public enum TranscriptMarkdownExporter {
    public static func markdown(for transcript: TranscriptSurface) -> String {
        var blocks: [String] = []
        for item in transcript.timelineItems {
            switch item.kind {
            case .message:
                guard let message = item.message, let heading = heading(for: message.role) else { continue }
                let body = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                blocks.append("## \(heading)\n\n\(body)")
            case .toolCard:
                guard let card = item.toolCard else { continue }
                let text = TranscriptItemTextFormatter.text(for: card)
                let fence = codeFence(for: text)
                blocks.append("### \(card.title)\n\n\(fence)\n\(text)\n\(fence)")
            }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The Markdown to export, or `nil` when there is nothing user-visible to export.
    public static func exportableMarkdown(for transcript: TranscriptSurface) -> String? {
        let markdown = markdown(for: transcript)
        return markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : markdown
    }

    /// The Markdown to put on the clipboard, retained as the clipboard-specific call site.
    public static func clipboardMarkdown(for transcript: TranscriptSurface) -> String? {
        exportableMarkdown(for: transcript)
    }

    /// Only user/assistant turns belong in a shared conversation. `.tool` turns are already
    /// filtered from the timeline, and `.system` is skipped so system-prompt content can
    /// never leak into an exported transcript.
    private static func heading(for role: ChatRole) -> String? {
        switch role {
        case .user:
            return "User"
        case .assistant:
            return "Assistant"
        case .system, .tool:
            return nil
        }
    }

    /// A backtick fence at least one longer than the longest backtick run in `body`, so a
    /// tool output containing ``` (e.g. a diff of a Markdown file) can never close the
    /// block early. Computed identically in the Swift and JS serializers.
    private static func codeFence(for body: String) -> String {
        var longestRun = 0
        var currentRun = 0
        for character in body {
            if character == "`" {
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return String(repeating: "`", count: max(3, longestRun + 1))
    }
}
