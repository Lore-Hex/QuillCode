import SwiftUI

struct QuillCodeTrustedRouterKeyLimitsView: View {
    var limits: [ProviderKeyLimitSurface]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(limits.enumerated()), id: \.element.id) { index, limit in
                if index > 0 {
                    Divider()
                        .opacity(0.45)
                }
                limitRow(limit)
                    .padding(.vertical, 9)
            }
        }
    }

    private func limitRow(_ limit: ProviderKeyLimitSurface) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(limit.periodLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                if let resetLabel = limit.resetLabel {
                    Text(resetLabel)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(limit.usageLabel)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                if let remainingLabel = limit.remainingLabel {
                    Text(remainingLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limit.detailLabel)
    }
}
