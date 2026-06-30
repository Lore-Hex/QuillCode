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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeSlashSuggestionIndex = 0
    @State private var activeFileMentionIndex = 0
    @State private var historyRecallIndex: Int?
    @State private var historySavedDraft: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .disabled(composer.isSending)
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
        guard let step = ComposerHistoryRecall.older(history: sentMessageHistory, currentIndex: historyRecallIndex) else {
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

private struct QuillCodeSlashSuggestionPanel: View {
    var suggestions: [SlashCommandSuggestionSurface]
    var selectedIndex: Int
    var onSelect: (SlashCommandSuggestionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Text("Slash commands")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .textCase(.uppercase)
                Spacer()
                Text("↑↓ choose · Tab complete")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(QuillCodePalette.muted)
            }

            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                QuillCodeSlashSuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex,
                    onSelect: onSelect
                )
            }
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct QuillCodeSlashSuggestionRow: View {
    var suggestion: SlashCommandSuggestionSurface
    var isSelected: Bool
    var onSelect: (SlashCommandSuggestionSurface) -> Void

    var body: some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
                Text(suggestion.usage)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .frame(minWidth: 128, maxWidth: 240, alignment: .leading)
                    .background(QuillCodePalette.panel.opacity(isSelected ? 0.94 : 0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? QuillCodePalette.blue : QuillCodePalette.muted.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .quillCodeFullRowButtonTarget(radius: 12)
            .background(isSelected ? QuillCodePalette.blue.opacity(0.13) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? QuillCodePalette.blue.opacity(0.24) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .accessibilityLabel("\(suggestion.usage), \(suggestion.title)")
        .accessibilityHint(suggestion.detail)
    }
}

private struct QuillCodeFileMentionSuggestionPanel: View {
    var suggestions: [FileMentionSuggestionSurface]
    var selectedIndex: Int
    var onSelect: (FileMentionSuggestionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Text("Files")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .textCase(.uppercase)
                Spacer()
                Text("↑↓ choose · Tab complete")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(QuillCodePalette.muted)
            }

            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                QuillCodeFileMentionSuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex,
                    onSelect: onSelect
                )
            }
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File mentions")
    }
}

private struct QuillCodeFileMentionSuggestionRow: View {
    var suggestion: FileMentionSuggestionSurface
    var isSelected: Bool
    var onSelect: (FileMentionSuggestionSurface) -> Void

    var body: some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
                Image(systemName: suggestion.kind == .directory ? "folder" : "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(suggestion.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if suggestion.isChanged {
                            changedBadge
                        }
                    }
                    Text(suggestion.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isSelected ? QuillCodePalette.blue : QuillCodePalette.muted.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .quillCodeFullRowButtonTarget(radius: 12)
            .background(isSelected ? QuillCodePalette.blue.opacity(0.13) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? QuillCodePalette.blue.opacity(0.24) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .accessibilityLabel("Mention \(suggestion.path)\(suggestion.kind == .directory ? ", directory" : "")\(suggestion.isChanged ? ", changed" : "")")
        .accessibilityHint(suggestion.directory.isEmpty ? "Workspace root" : "In \(suggestion.directory)")
    }

    private var changedBadge: some View {
        Text("Changed")
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(QuillCodePalette.yellow)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(QuillCodePalette.yellow.opacity(0.16))
            )
            .accessibilityHidden(true)
    }
}
