import SwiftUI

struct QuillCodeTopBarIdentityView: View {
    var topBar: TopBarSurface

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(topBar.primaryTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(topBar.subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .truncationMode(.middle)

            if let branchStatusLabel = topBar.branchStatusLabel {
                statusChip(branchStatusLabel)
                    .accessibilityHidden(true)
            }

            if let usageStatusLabel = topBar.usageStatusLabel {
                statusChip(usageStatusLabel)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusChip(_ label: String) -> some View {
        Text(label)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(QuillCodePalette.muted)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(QuillCodePalette.background.opacity(0.6))
            )
    }
}
