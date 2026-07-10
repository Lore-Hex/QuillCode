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
    var onAddImagesRequested: () -> Void = {}
    var onRemoveImage: (UUID) -> Void = { _ in }
    var onStop: () -> Void
    var onDeleteFollowUp: (UUID) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeSlashSuggestionIndex = 0
    @State private var activeModelCommandIndex = 0
    @State private var activeFileMentionIndex = 0
    @State private var historyRecallIndex: Int?
    @State private var historySavedDraft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let planProgress = composer.planProgress {
                QuillCodePlanProgressStrip(progress: planProgress, reduceMotion: reduceMotion)
            }
            if !modelCommandSuggestions.isEmpty {
                QuillCodeModelCommandSuggestionPanel(
                    suggestions: modelCommandSuggestions,
                    selectedIndex: activeModelCommandIndex,
                    onSelect: acceptModelCommand
                )
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
            } else if let modelCommandEmptyCopy {
                QuillCodeModelCommandEmptyPanel(copy: modelCommandEmptyCopy)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
            } else if !slashSuggestions.isEmpty {
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
            activeModelCommandIndex = 0
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
        .onChange(of: modelCommandSuggestions) { _, suggestions in
            if suggestions.isEmpty {
                activeModelCommandIndex = 0
            } else {
                activeModelCommandIndex = min(activeModelCommandIndex, suggestions.count - 1)
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
                QuillCodeFollowUpQueueView(
                    items: composer.followUpQueue,
                    onDelete: onDeleteFollowUp
                )
            }

            if !composer.attachments.isEmpty {
                QuillCodeImageAttachmentStrip(
                    attachments: composer.attachments,
                    onRemove: onRemoveImage
                )
            }

            HStack(alignment: .bottom, spacing: QuillCodeMetrics.controlClusterSpacing) {
                QuillCodeComposerTextField(
                    placeholder: composer.placeholder,
                    draft: $draft,
                    isFocused: isFocused,
                    onDownArrow: handleDownArrow,
                    onUpArrow: handleUpArrow,
                    onTab: handleTab,
                    onReturn: handleReturn,
                    onSend: onSend
                )
                QuillCodeComposerActionButton(
                    isSending: composer.isSending,
                    canSendDraft: canSendDraft,
                    onSend: onSend,
                    onStop: onStop
                )
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
        if !modelCommandSuggestions.isEmpty
            || modelCommandEmptyCopy != nil
            || !slashSuggestions.isEmpty
            || !fileMentionSuggestions.isEmpty {
            return QuillCodePalette.blue.opacity(0.34)
        }
        return Color.white.opacity(isFocused.wrappedValue ? 0.18 : 0.08)
    }

    /// Catalog model suggestions for the `/model ` sub-search. Takes precedence over the general
    /// slash popup (see `slashSuggestions`) so `/model gpt` browses models instead of re-showing the
    /// `/model` command row. Uses the topBar's live categories, so prices are the current catalog's.
    private var modelCommandSuggestions: [ModelCommandSuggestionSurface] {
        SlashModelCatalogSearch.suggestions(for: draft, categories: topBar.modelCategories)
    }

    private var modelCommandEmptyCopy: ModelPickerEmptyStateCopy? {
        SlashModelCatalogSearch.emptyStateCopy(
            for: draft,
            categories: topBar.modelCategories,
            catalogSource: topBar.modelCatalogSource,
            catalogStatusDetail: topBar.modelCatalogStatusDetail
        )
    }

    private var slashSuggestions: [SlashCommandSuggestionSurface] {
        // Once the user has committed to `/model ` and is querying a model, the model sub-search
        // owns the popup; suppress the top-level slash list so the two never both render.
        guard !SlashModelCatalogSearch.isActive(in: draft) else { return [] }
        return SlashCommandCatalog.suggestions(for: draft)
    }

    private var fileMentionSuggestions: [FileMentionSuggestionSurface] {
        guard slashSuggestions.isEmpty,
              modelCommandSuggestions.isEmpty,
              modelCommandEmptyCopy == nil else { return [] }
        return FileMentionCatalog.suggestions(for: draft, in: fileMentionIndex, changedPaths: changedFilePaths)
    }

    private var canSendDraft: Bool {
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !composer.attachments.isEmpty)
            && !composer.isSending
            && modelCommandEmptyCopy == nil
    }

    private var composerAccessoryBar: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Button(action: onAddImagesRequested) {
                Image(systemName: "photo.badge.plus")
                    .font(.callout.weight(.semibold))
                    .quillCodeIconButtonTarget(
                        size: QuillCodeMetrics.minimumHitTarget,
                        radius: QuillCodeMetrics.composerControlRadius
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .foregroundStyle(QuillCodePalette.muted)
            .help("Attach images")
            .accessibilityLabel("Attach images")
            .accessibilityIdentifier("quillcode-attach-images-button")

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

    private func handleDownArrow() -> KeyPress.Result {
        if !modelCommandSuggestions.isEmpty {
            activeModelCommandIndex = min(activeModelCommandIndex + 1, modelCommandSuggestions.count - 1)
            return .handled
        }
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

    private func handleUpArrow() -> KeyPress.Result {
        if !modelCommandSuggestions.isEmpty {
            activeModelCommandIndex = max(activeModelCommandIndex - 1, 0)
            return .handled
        }
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

    private func handleTab() -> KeyPress.Result {
        if acceptActiveModelCommand() { return .handled }
        if acceptActiveSlashSuggestion(force: true) { return .handled }
        if acceptActiveFileMention(force: true) { return .handled }
        return .ignored
    }

    private func handleReturn() -> KeyPress.Result {
        if acceptActiveModelCommand() { return .handled }
        if modelCommandEmptyCopy != nil { return .handled }
        if acceptActiveSlashSuggestion(force: false) { return .handled }
        if acceptActiveFileMention(force: false) { return .handled }
        return .ignored
    }

    private func acceptActiveModelCommand() -> Bool {
        guard !modelCommandSuggestions.isEmpty else { return false }
        let index = min(max(activeModelCommandIndex, 0), modelCommandSuggestions.count - 1)
        acceptModelCommand(modelCommandSuggestions[index])
        return true
    }

    /// Accepting a model row switches the thread's model NOW through the shared live writer
    /// (`onSetModel` → `setModel` → `thread.model` + persistence), then clears the composer so the
    /// consumed `/model` command never lingers as sendable text. This is the SAME writer the picker
    /// and the typed `/model <id>` command use — no second, divergent model-setting path.
    private func acceptModelCommand(_ suggestion: ModelCommandSuggestionSurface) {
        onSetModel(suggestion.modelID)
        draft = ""
        activeModelCommandIndex = 0
        DispatchQueue.main.async {
            isFocused.wrappedValue = true
        }
    }

    private func acceptActiveSlashSuggestion(force: Bool) -> Bool {
        guard !slashSuggestions.isEmpty else { return false }
        let index = min(max(activeSlashSuggestionIndex, 0), slashSuggestions.count - 1)
        let suggestion = slashSuggestions[index]
        // Tab (force) always completes. On Enter (non-force), never RE-accept a completion the user
        // has already typed PAST: if the draft already begins with the space-terminated insertText
        // and carries an argument (e.g. `/skill code-review` vs the `/skill ` insert), re-accepting
        // would reset the draft to the bare command and DROP the argument, blocking submission.
        // Enter then falls through to submit the fully-typed command instead.
        if !force,
           suggestion.insertText.hasSuffix(" "),
           draft.hasPrefix(suggestion.insertText),
           draft.count > suggestion.insertText.count {
            return false
        }
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
