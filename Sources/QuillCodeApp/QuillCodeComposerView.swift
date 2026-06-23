import SwiftUI
import QuillCodeCore

struct QuillCodeComposerView: View {
    var composer: ComposerSurface
    var topBar: TopBarSurface
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !composer.slashSuggestions.isEmpty {
                QuillCodeSlashSuggestionPanel(
                    suggestions: composer.slashSuggestions,
                    selectedIndex: activeSlashSuggestionIndex,
                    onSelect: acceptSlashSuggestion
                )
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
            }

            composerSurface
        }
        .padding(12)
        .background(QuillCodePalette.panel)
        .onChange(of: draft) { _, _ in
            activeSlashSuggestionIndex = 0
        }
        .onChange(of: composer.slashSuggestions) { _, suggestions in
            if suggestions.isEmpty {
                activeSlashSuggestionIndex = 0
            } else {
                activeSlashSuggestionIndex = min(activeSlashSuggestionIndex, suggestions.count - 1)
            }
        }
    }

    private var composerSurface: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
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
        if !composer.slashSuggestions.isEmpty {
            return QuillCodePalette.blue.opacity(0.34)
        }
        return Color.white.opacity(isFocused.wrappedValue ? 0.18 : 0.08)
    }

    private var composerAccessoryBar: some View {
        HStack(spacing: 8) {
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
            .frame(minHeight: 44)
            .disabled(composer.isSending)
            .focused(isFocused)
            .onKeyPress(.downArrow) {
                guard !composer.slashSuggestions.isEmpty else { return .ignored }
                activeSlashSuggestionIndex = min(activeSlashSuggestionIndex + 1, composer.slashSuggestions.count - 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard !composer.slashSuggestions.isEmpty else { return .ignored }
                activeSlashSuggestionIndex = max(activeSlashSuggestionIndex - 1, 0)
                return .handled
            }
            .onKeyPress(.tab) {
                guard acceptActiveSlashSuggestion(force: true) else { return .ignored }
                return .handled
            }
            .onKeyPress(.return) {
                guard acceptActiveSlashSuggestion(force: false) else { return .ignored }
                return .handled
            }
            .onSubmit(onSend)
            .accessibilityLabel("Message")
    }

    @ViewBuilder
    private var composerAction: some View {
        if composer.isSending {
            Button(action: onStop) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(minWidth: 90, minHeight: 46)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .background(QuillCodePalette.red)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerControlRadius, style: .continuous))
            .keyboardShortcut(.cancelAction)
            .help("Stop the current run")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.headline.weight(.semibold))
                    .frame(width: 46, height: 46)
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .background(composer.canSend ? QuillCodePalette.blue : QuillCodePalette.background.opacity(0.72))
            .foregroundStyle(composer.canSend ? Color.white : QuillCodePalette.muted)
            .clipShape(RoundedRectangle(cornerRadius: QuillCodeMetrics.composerControlRadius, style: .continuous))
            .disabled(!composer.canSend)
            .help("Send")
            .accessibilityLabel("Send message")
        }
    }

    private func acceptActiveSlashSuggestion(force: Bool) -> Bool {
        guard !composer.slashSuggestions.isEmpty else { return false }
        let index = min(max(activeSlashSuggestionIndex, 0), composer.slashSuggestions.count - 1)
        let suggestion = composer.slashSuggestions[index]
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
}

private struct QuillCodeSlashSuggestionPanel: View {
    var suggestions: [SlashCommandSuggestionSurface]
    var selectedIndex: Int
    var onSelect: (SlashCommandSuggestionSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
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
            HStack(alignment: .center, spacing: 12) {
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
            .frame(maxWidth: .infinity, minHeight: QuillCodeMetrics.minimumHitTarget, alignment: .leading)
            .background(isSelected ? QuillCodePalette.blue.opacity(0.13) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? QuillCodePalette.blue.opacity(0.24) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .accessibilityLabel("\(suggestion.usage), \(suggestion.title)")
        .accessibilityHint(suggestion.detail)
    }
}
