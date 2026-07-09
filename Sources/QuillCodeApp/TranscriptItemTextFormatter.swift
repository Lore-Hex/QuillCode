import QuillCodeCore

/// Shared per-transcript-item text shaping used by BOTH the per-item copy button and the
/// whole-conversation Markdown export, so the two can never drift. A tool card's text is
/// its output, else its input, else its title/subtitle.
public enum TranscriptItemTextFormatter {
    public static func text(for card: ToolCardState) -> String {
        if let outputJSON = card.outputJSON,
           !outputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return outputJSON
        }
        if let inputJSON = card.inputJSON,
           !inputJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return inputJSON
        }
        return [WorkspaceToolDisplayNameBuilder.displayName(for: card.title), card.subtitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
