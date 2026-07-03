import SwiftUI
import QuillCodeCore
import QuillCodeTools

struct QuillCodeComposerView: View {
    var composer: ComposerSurface
    var topBar: TopBarSurface
    var fileMentionIndex: WorkspaceFileIndex = WorkspaceFileIndex()
    var changedFilePaths: Set<String> = []
    var sentMessageHistory: [String] = []
    @Binding var draft: String
    @Binding var isModelPickerPresented: Bool
    var isFocused: FocusState<Bool>.Binding
    var onSetMode: (AgentMode) -> Void
    var onSetModel: (String) -> Void
    var onToggleModelFavorite: (String) -> Void
    var onSend: () -> Void
    var onStop: () -> Void
    var onDeleteFollowUp: (UUID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeSlashSuggestionIndex = 0
    @State private var activeFileMentionIndex = 0
    @State private var historyRecallIndex: Int?
    @State private var historySavedDraft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let planProgress = composer.planProgress {
                QuillCodePlanProgressStrip(progress: planProgress, reduceMotion: reduceMotion)
            }
            if !slashSuggestions.isEmpty {
                QuillCodeSlashSuggestionPanel(
                    suggestions: slashSuggestions,
                    selectedIndex: activeSlashSuggestionIndex,
                    onSelect: acceptSlashSuggestion
                )
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
            } else if !fileMentionSuggestions.isEmpty {
                QuillCodeFileMentionSuggestionPanel(
                    suggestions: fileMentionSuggestions,
                    selectedIndex: activeFileMentionIndex,
                    onSelect: acceptFileMention
                )
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
            }

            composerSurface
        }
        .padding(12)
        .background(QuillCodePalette.panel)
        .onChange(of: draft) { _, newValue in
            activeSlashSuggestionIndex = 0
            activeFileMentionIndex = 0
            if newValue.isEmpty {
                historyRecallIndex = nil
                historySavedDraft = nil
            }
        }
        .onChange(of: slashSuggestions) { _, suggestions in
            if suggestions.isEmpty {
                activeSlashSuggestionIndex = 0
            } else {
                activeSlashSuggestionIndex = min(activeSlashSuggestionIndex, suggestions.count - 1)
            }
        }
        .onChange(of: fileMentionSuggestions) { _, suggestions in
            if suggestions.isEmpty {
                activeFileMentionIndex = 0
            } else {
                activeFileMentionIndex = min(activeFileMentionIndex, suggestions.count - 1)
            }
        }
        .onChange(of: sentMessageHistory) { _, _ in
            // Switching threads swaps the recall history (and may restore a non-empty
            // draft), so reset the recall cursor to avoid replaying the prior thread.
            historyRecallIndex = nil
            historySavedDraft = nil
        }
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !composer.followUpQueue.isEmpty {
                followUpQueueChips
            }

            HStack(alignment: .bottom, spacing: QuillCodeMetrics.controlClusterSpacing) {
                composerField
                composerAction
            }

            composerAccessoryBar
        }
        .padding(8)
        .background(QuillCodePalette.background.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: QuillCodeMetrics.composerSurfaceRadius, style: .continuous)
                .stroke(composerSurfaceStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerSurfaceRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Message composer")
    }

    private var composerSurfaceStroke: Color {
        if !slashSuggestions.isEmpty || !fileMentionSuggestions.isEmpty {
            return QuillCodePalette.blue.opacity(0.34)
        }
        return Color.white.opacity(isFocused.wrappedValue ? 0.18 : 0.08)
    }

    /// The queued follow-up chips shown above the input while a run is live. Each chip shows
    /// the queued prompt and a delete button that removes it before it drains. Stacked one per
    /// row (oldest first) so a long queued prompt stays readable and the drain order is clear.
    private var followUpQueueChips: some View {
        VStack(alignment: .leading, spacing: QuillCodeMetrics.denseControlClusterSpacing) {
            ForEach(composer.followUpQueue) { item in
                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    Text(item.text)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(QuillCodePalette.blue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        onDeleteFollowUp(item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .quillCodeIconButtonTarget(size: 22, radius: 6)
                    }
                    .buttonStyle(QuillCodePressableButtonStyle())
                    .foregroundStyle(QuillCodePalette.muted)
                    .help("Remove queued follow-up")
                    .accessibilityLabel("Remove queued follow-up")
                    .accessibilityIdentifier("quillcode-followup-delete")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QuillCodePalette.blue.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(QuillCodePalette.blue.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("quillcode-followup-chip")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Queued follow-ups")
    }

    private var slashSuggestions: [SlashCommandSuggestionSurface] {
        SlashCommandCatalog.suggestions(for: draft)
    }

    private var fileMentionSuggestions: [FileMentionSuggestionSurface] {
        guard slashSuggestions.isEmpty else { return [] }
        return FileMentionCatalog.suggestions(for: draft, in: fileMentionIndex, changedPaths: changedFilePaths)
    }

    private var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !composer.isSending
    }

    private var composerAccessoryBar: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            QuillCodeModelPickerView(
                topBar: topBar,
                isPresented: $isModelPickerPresented,
                onSetModel: onSetModel,
                onToggleModelFavorite: onToggleModelFavorite
            )
            .layoutPriority(2)

            QuillCodeModePickerButton(
                modeLabel: topBar.modeLabel,
                onSetMode: onSetMode
            )

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Composer model and safety controls")
    }

    private var composerField: some View {
        TextField(composer.placeholder, text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...5)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .quillCodeTextEntryTarget()
            // Never locks during a run: typing stays enabled so a follow-up can be entered and
            // queued (Enter enqueues while the run is live, drains at the next turn boundary).
            .focused(isFocused)
            .onKeyPress(.downArrow) {
                if !slashSuggestions.isEmpty {
                    activeSlashSuggestionIndex = min(activeSlashSuggestionIndex + 1, slashSuggestions.count - 1)
                    return .handled
                }
                if !fileMentionSuggestions.isEmpty {
                    activeFileMentionIndex = min(activeFileMentionIndex + 1, fileMentionSuggestions.count - 1)
                    return .handled
                }
                return recallNewerHistory() ? .handled : .ignored
            }
            .onKeyPress(.upArrow) {
                if !slashSuggestions.isEmpty {
                    activeSlashSuggestionIndex = max(activeSlashSuggestionIndex - 1, 0)
                    return .handled
                }
                if !fileMentionSuggestions.isEmpty {
                    activeFileMentionIndex = max(activeFileMentionIndex - 1, 0)
                    return .handled
                }
                return recallOlderHistory() ? .handled : .ignored
            }
            .onKeyPress(.tab) {
                if acceptActiveSlashSuggestion(force: true) { return .handled }
                if acceptActiveFileMention(force: true) { return .handled }
                return .ignored
            }
            .onKeyPress(.return) {
                if acceptActiveSlashSuggestion(force: false) { return .handled }
                if acceptActiveFileMention(force: false) { return .handled }
                return .ignored
            }
            .onSubmit(onSend)
            .accessibilityLabel("Message")
            .accessibilityIdentifier("quillcode-composer-input")
    }

    @ViewBuilder
    private var composerAction: some View {
        if composer.isSending {
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .quillCodeTextButtonTarget(
                        minWidth: 90,
                        minHeight: 46,
                        radius: QuillCodeMetrics.composerControlRadius
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .background(QuillCodePalette.red)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerControlRadius, style: .continuous))
            .keyboardShortcut(.cancelAction)
            .help("Stop the current run")
            .accessibilityIdentifier("quillcode-stop-button")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.semibold))
                    .quillCodeIconButtonTarget(
                        size: 46,
                        radius: QuillCodeMetrics.composerControlRadius
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .background(canSendDraft ? QuillCodePalette.blue : QuillCodePalette.background.opacity(0.72))
            .foregroundStyle(canSendDraft ? Color.white : QuillCodePalette.muted)
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerControlRadius, style: .continuous))
            .disabled(!canSendDraft)
            .help("Send")
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("quillcode-send-button")
        }
    }

    private func acceptActiveSlashSuggestion(force: Bool) -> Bool {
        guard !slashSuggestions.isEmpty else { return false }
        let index = min(max(activeSlashSuggestionIndex, 0), slashSuggestions.count - 1)
        let suggestion = slashSuggestions[index]
        guard force || draft != suggestion.insertText || suggestion.insertText.hasSuffix(" ") else {
            return false
        }
        acceptSlashSuggestion(suggestion)
        return true
    }

    private func acceptSlashSuggestion(_ suggestion: SlashCommandSuggestionSurface) {
        draft = suggestion.insertText
        DispatchQueue.main.async {
            isFocused.wrappedValue = true
        }
    }

    private func acceptActiveFileMention(force: Bool) -> Bool {
        guard !fileMentionSuggestions.isEmpty else { return false }
        let index = min(max(activeFileMentionIndex, 0), fileMentionSuggestions.count - 1)
        let suggestion = fileMentionSuggestions[index]
        guard force || draft != suggestion.insertText else { return false }
        acceptFileMention(suggestion)
        return true
    }

    private func acceptFileMention(_ suggestion: FileMentionSuggestionSurface) {
        draft = suggestion.insertText
        DispatchQueue.main.async {
            isFocused.wrappedValue = true
        }
    }

    private func showingUneditedRecall(at index: Int?) -> Bool {
        guard let index, sentMessageHistory.indices.contains(index) else { return false }
        return draft == sentMessageHistory[index]
    }

    private func recallOlderHistory() -> Bool {
        guard !sentMessageHistory.isEmpty else { return false }
        if historyRecallIndex == nil {
            // Only begin recall from an empty composer so multiline editing keeps Up.
            guard draft.isEmpty else { return false }
            guard let step = ComposerHistoryRecall.older(history: sentMessageHistory, currentIndex: nil) else {
                return false
            }
            historySavedDraft = draft
            historyRecallIndex = step.index
            draft = step.draft
            return true
        }
        // Continue only while the recalled message is unedited.
        guard showingUneditedRecall(at: historyRecallIndex) else { return false }
        guard let step = ComposerHistoryRecall.older(
            history: sentMessageHistory,
            currentIndex: historyRecallIndex
        ) else {
            return false
        }
        historyRecallIndex = step.index
        draft = step.draft
        return true
    }

    private func recallNewerHistory() -> Bool {
        guard let index = historyRecallIndex, showingUneditedRecall(at: index) else { return false }
        if let step = ComposerHistoryRecall.newer(history: sentMessageHistory, currentIndex: index) {
            historyRecallIndex = step.index
            draft = step.draft
        } else {
            draft = historySavedDraft ?? ""
            historyRecallIndex = nil
            historySavedDraft = nil
        }
        return true
    }
}
