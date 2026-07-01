import SwiftUI
import QuillCodeTools

struct QuillCodeSlashSuggestionPanel: View {
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

struct QuillCodeFileMentionSuggestionPanel: View {
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
