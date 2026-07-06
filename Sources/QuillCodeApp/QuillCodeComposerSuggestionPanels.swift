import SwiftUI
import QuillCodeTools

struct QuillCodeSlashSuggestionPanel: View {
    var suggestions: [SlashCommandSuggestionSurface]
    var selectedIndex: Int
    var onSelect: (SlashCommandSuggestionSurface) -> Void

    var body: some View {
        QuillCodeSuggestionPanel(title: "Slash commands") {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                QuillCodeSlashSuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex,
                    onSelect: onSelect
                )
            }
        }
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

                QuillCodeSuggestionRowArrow(isSelected: isSelected)
            }
            .quillCodeSuggestionRowChrome(isSelected: isSelected)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget(radius: 12)
        .accessibilityLabel("\(suggestion.usage), \(suggestion.title)")
        .accessibilityHint(suggestion.detail)
    }
}

struct QuillCodeModelCommandSuggestionPanel: View {
    var suggestions: [ModelCommandSuggestionSurface]
    var selectedIndex: Int
    var onSelect: (ModelCommandSuggestionSurface) -> Void

    var body: some View {
        QuillCodeSuggestionPanel(title: "Models", accessibilityLabel: "Model switch") {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                QuillCodeModelCommandSuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex,
                    onSelect: onSelect
                )
            }
        }
    }
}

struct QuillCodeModelCommandEmptyPanel: View {
    var copy: ModelPickerEmptyStateCopy

    var body: some View {
        QuillCodeSuggestionPanel(
            title: "Models",
            keyboardHint: "Keep typing to search",
            accessibilityLabel: "No matching models"
        ) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                Text(copy.detail)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote = copy.footnote {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.muted.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
}

private struct QuillCodeModelCommandSuggestionRow: View {
    var suggestion: ModelCommandSuggestionSurface
    var isSelected: Bool
    var onSelect: (ModelCommandSuggestionSurface) -> Void

    var body: some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
                Image(systemName: "diamond")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(suggestion.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if suggestion.isCurrent {
                            currentBadge
                        }
                    }
                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if !suggestion.priceLabel.isEmpty {
                    Text(suggestion.priceLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .layoutPriority(1)
                }

                QuillCodeSuggestionRowArrow(isSelected: isSelected)
            }
            .quillCodeSuggestionRowChrome(isSelected: isSelected)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget(radius: 12)
        .accessibilityLabel(
            "Switch to \(suggestion.title)"
                + "\(suggestion.isCurrent ? ", current" : "")"
        )
        .accessibilityHint(
            suggestion.priceLabel.isEmpty
                ? suggestion.detail
                : "\(suggestion.detail), \(suggestion.priceLabel)"
        )
    }

    private var currentBadge: some View {
        Text("Current")
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(QuillCodePalette.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(QuillCodePalette.blue.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

struct QuillCodeFileMentionSuggestionPanel: View {
    var suggestions: [FileMentionSuggestionSurface]
    var selectedIndex: Int
    var onSelect: (FileMentionSuggestionSurface) -> Void

    var body: some View {
        QuillCodeSuggestionPanel(title: "Files", accessibilityLabel: "File mentions") {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                QuillCodeFileMentionSuggestionRow(
                    suggestion: suggestion,
                    isSelected: index == selectedIndex,
                    onSelect: onSelect
                )
            }
        }
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

                QuillCodeSuggestionRowArrow(isSelected: isSelected)
            }
            .quillCodeSuggestionRowChrome(isSelected: isSelected)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeFullRowButtonTarget(radius: 12)
        .accessibilityLabel(
            "Mention \(suggestion.path)"
                + "\(suggestion.kind == .directory ? ", directory" : "")"
                + "\(suggestion.isChanged ? ", changed" : "")"
        )
        .accessibilityHint(suggestion.directory.isEmpty ? "Workspace root" : "In \(suggestion.directory)")
    }

    private var changedBadge: some View {
        Text("Changed")
            .font(.system(size: 9, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(QuillCodePalette.yellow)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(QuillCodePalette.yellow.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

private struct QuillCodeSuggestionPanel<Rows: View>: View {
    var title: String
    var keyboardHint = "↑↓ choose · Tab complete"
    var accessibilityLabel: String?
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .textCase(.uppercase)
                Spacer()
                Text(keyboardHint)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(QuillCodePalette.muted)
            }
            rows
        }
        .padding(10)
        .background(QuillCodePalette.background.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

private struct QuillCodeSuggestionRowArrow: View {
    var isSelected: Bool

    var body: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(isSelected ? QuillCodePalette.blue : QuillCodePalette.muted.opacity(0.7))
            .accessibilityHidden(true)
    }
}

private struct QuillCodeSuggestionRowChrome: ViewModifier {
    var isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? QuillCodePalette.blue.opacity(0.13) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? QuillCodePalette.blue.opacity(0.24) : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension View {
    func quillCodeSuggestionRowChrome(isSelected: Bool) -> some View {
        modifier(QuillCodeSuggestionRowChrome(isSelected: isSelected))
    }
}
