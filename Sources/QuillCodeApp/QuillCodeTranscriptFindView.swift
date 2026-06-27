import SwiftUI

struct QuillCodeTranscriptFindMatch: Identifiable, Hashable {
    var id: String { timelineItemID }
    var timelineItemID: String
    var label: String

    static func matches(in transcript: TranscriptSurface, query: String) -> [QuillCodeTranscriptFindMatch] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        return transcript.timelineItems.compactMap { item in
            let haystack = searchableText(for: item)
            guard haystack.localizedCaseInsensitiveContains(normalizedQuery) else { return nil }
            return QuillCodeTranscriptFindMatch(
                timelineItemID: item.id,
                label: label(for: item)
            )
        }
    }

    private static func searchableText(for item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            return [
                item.message?.role.rawValue,
                item.message?.text
            ].compactMap { $0 }.joined(separator: "\n")
        case .toolCard:
            guard let card = item.toolCard else { return "" }
            return [
                card.title,
                card.subtitle,
                card.inputJSON,
                card.outputJSON,
                card.artifacts.map(\.label).joined(separator: "\n")
            ].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private static func label(for item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            return item.message?.role.rawValue.capitalized ?? "Message"
        case .toolCard:
            return item.toolCard?.title ?? "Tool"
        }
    }
}

struct QuillCodeTranscriptFindBar: View {
    @Binding var query: String
    var activeIndex: Int
    var matchCount: Int
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onClose: () -> Void

    @FocusState private var isFocused: Bool

    private var statusText: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Type to find" }
        guard matchCount > 0 else { return "No results" }
        return "\(min(activeIndex + 1, matchCount)) of \(matchCount)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(QuillCodePalette.blue)
            TextField("Find in chat", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(onNext)
            Text(statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(matchCount > 0 || query.isEmpty ? QuillCodePalette.muted : QuillCodePalette.yellow)
                .frame(minWidth: 86, alignment: .trailing)
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .quillCodeHitTarget()
            .disabled(matchCount == 0)
            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .quillCodeHitTarget()
            .disabled(matchCount == 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .quillCodeHitTarget()
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(QuillCodePalette.panel)
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}
