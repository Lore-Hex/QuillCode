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
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            compactLayout
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

    private var horizontalLayout: some View {
        HStack(spacing: 10) {
            searchIcon
            queryField
            statusLabel
                .frame(minWidth: 86, alignment: .trailing)
            navigationButtons
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                searchIcon
                queryField
            }
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                statusLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                navigationButtons
            }
        }
    }

    private var searchIcon: some View {
        Image(systemName: "text.magnifyingglass")
            .quillCodeDecorativeIconFrame()
            .foregroundStyle(QuillCodePalette.blue)
    }

    private var queryField: some View {
        TextField("Find in chat", text: $query)
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .quillCodeTextEntryTarget()
            .onSubmit(onNext)
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.caption.monospacedDigit())
            .foregroundStyle(matchCount > 0 || query.isEmpty ? QuillCodePalette.muted : QuillCodePalette.yellow)
    }

    private var navigationButtons: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeIconButtonTarget()
            .disabled(matchCount == 0)
            .help("Previous match")
            .accessibilityLabel("Previous match")

            Button(action: onNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeIconButtonTarget()
            .disabled(matchCount == 0)
            .help("Next match")
            .accessibilityLabel("Next match")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .quillCodeIconButtonTarget()
            .keyboardShortcut(.cancelAction)
            .help("Close find")
            .accessibilityLabel("Close find")
        }
    }
}
