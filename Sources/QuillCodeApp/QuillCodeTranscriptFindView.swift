import SwiftUI

/// The find bar's per-item match. This is now a thin projection of the pure
/// ``TranscriptSearchIndex`` (literal, case-insensitive, unicode-safe matching with
/// highlight ranges) so the native find bar, the desktop coordinator, and the HTML harness all
/// share one matching definition.
struct QuillCodeTranscriptFindMatch: Identifiable, Hashable {
    var id: String { timelineItemID }
    var timelineItemID: String
    var label: String
    /// Character-offset ranges of each occurrence within the item's searchable text, for
    /// highlighting. Empty is impossible for a `QuillCodeTranscriptFindMatch` (a non-matching
    /// item is dropped).
    var ranges: [TranscriptSearchIndex.MatchRange]

    static func matches(in transcript: TranscriptSurface, query: String) -> [QuillCodeTranscriptFindMatch] {
        TranscriptSearchIndex.build(transcript: transcript, query: query).matches.map {
            QuillCodeTranscriptFindMatch(
                timelineItemID: $0.timelineItemID,
                label: $0.label,
                ranges: $0.ranges
            )
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
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            searchIcon
            queryField
            statusLabel
                .frame(minWidth: 86, alignment: .trailing)
            navigationButtons
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
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
            .accessibilityIdentifier("quillcode-transcript-find-input")
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
