import SwiftUI

struct QuillCodeModelCategorySection: View {
    var category: ModelCategorySurface
    @Binding var expandedModelID: String?
    var highlightedModelID: String?
    var reduceMotion: Bool
    var onSetModel: (ModelOptionSurface) -> Void
    var onToggleModelFavorite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(category.category.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .padding(.horizontal, 10)
            ForEach(category.models) { option in
                QuillCodeModelRow(
                    option: option,
                    isExpanded: expandedModelID == option.id,
                    isHighlighted: highlightedModelID == option.id,
                    reduceMotion: reduceMotion,
                    onSelect: onSetModel,
                    onToggleExpanded: toggleExpanded,
                    onToggleFavorite: onToggleModelFavorite
                )
            }
        }
    }

    private func toggleExpanded(_ option: ModelOptionSurface) {
        quillCodeWithAnimation(.easeOut(duration: 0.16), reduceMotion: reduceMotion) {
            expandedModelID = expandedModelID == option.id ? nil : option.id
        }
    }
}

struct QuillCodeModelRow: View {
    var option: ModelOptionSurface
    var isExpanded: Bool
    var isHighlighted: Bool
    var reduceMotion: Bool
    var onSelect: (ModelOptionSurface) -> Void
    var onToggleExpanded: (ModelOptionSurface) -> Void
    var onToggleFavorite: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    onSelect(option)
                } label: {
                    HStack(spacing: 10) {
                        modelSummary
                        Spacer(minLength: 10)
                        if option.isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(QuillCodePalette.green)
                                .accessibilityLabel("Current model")
                        }
                    }
                    .quillCodeFullRowButtonTarget(radius: 10)
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .help(option.metadataDetails.joined(separator: "\n"))
                .accessibilityHint(option.metadataDetails.joined(separator: ", "))

                HStack(spacing: QuillCodeMetrics.denseControlClusterSpacing) {
                    modelActionButton(
                        systemImage: isExpanded ? "info.circle.fill" : "info.circle",
                        tint: isExpanded ? QuillCodePalette.blue : QuillCodePalette.muted,
                        title: isExpanded ? "Hide model details" : "Show model details"
                    ) {
                        onToggleExpanded(option)
                    }

                    modelActionButton(
                        systemImage: option.isFavorite ? "star.fill" : "star",
                        tint: option.isFavorite ? QuillCodePalette.yellow : QuillCodePalette.muted,
                        title: option.isFavorite ? "Remove favorite model" : "Favorite model"
                    ) {
                        onToggleFavorite(option.id)
                    }
                }
            }

            if isExpanded {
                QuillCodeModelDetails(option: option)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(rowStroke, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            if option.isSelected {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(QuillCodePalette.blue.opacity(0.72))
                    .frame(width: 3)
                    .padding(.vertical, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var modelSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(option.detailTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(option.metadataSummary)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.middle)
            if !option.badges.isEmpty {
                badgeRow
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackground: Color {
        if option.isSelected {
            return QuillCodePalette.blue.opacity(isHighlighted ? 0.08 : 0.045)
        }
        return isHighlighted ? Color.white.opacity(0.05) : Color.clear
    }

    private var rowStroke: Color {
        if isHighlighted {
            return QuillCodePalette.blue.opacity(0.42)
        }
        return option.isSelected ? QuillCodePalette.blue.opacity(0.16) : Color.clear
    }

    private var badgeRow: some View {
        HStack(spacing: 5) {
            ForEach(option.badges.prefix(3), id: \.self) { badge in
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(badgeForeground(for: badge))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeBackground(for: badge))
                    .clipShape(Capsule())
            }
        }
        .lineLimit(1)
    }

    private func badgeForeground(for badge: String) -> Color {
        switch badge {
        case "Current":
            return QuillCodePalette.green
        case "Default", "Recommended":
            return QuillCodePalette.blue
        case "Favorite":
            return QuillCodePalette.yellow
        default:
            return QuillCodePalette.muted
        }
    }

    private func badgeBackground(for badge: String) -> Color {
        badgeForeground(for: badge).opacity(0.12)
    }

    private func modelActionButton(
        systemImage: String,
        tint: Color,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .quillCodeIconButtonTarget()
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .help(title)
        .accessibilityLabel(title)
    }
}

struct QuillCodeModelDetails: View {
    var option: ModelOptionSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .opacity(0.28)

            Text(option.capabilitySummary)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 5) {
                ForEach(option.metadataRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.muted)
                            .frame(width: 62, alignment: .leading)
                        Text(row.value)
                            .font(.caption2.monospaced())
                            .foregroundStyle(QuillCodePalette.text)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
