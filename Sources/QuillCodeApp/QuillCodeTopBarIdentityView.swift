import SwiftUI

struct QuillCodeTopBarIdentityView: View {
    var topBar: TopBarSurface

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
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
            }
            .layoutPriority(2)

            if let branchStatusLabel = topBar.branchStatusLabel {
                statusChip(branchStatusLabel)
                    .accessibilityHidden(true)
            }

            if let tokenBudget = topBar.tokenBudget {
                tokenBudgetView(tokenBudget)
                    .help(tokenBudget.accessibilityLabel)
                    .accessibilityLabel(tokenBudget.accessibilityLabel)
                    .layoutPriority(1)
            } else if topBar.spendStatusLabel == nil,
                      let usageStatusLabel = topBar.usageStatusLabel {
                statusChip(usageStatusLabel)
                    .help(usageStatusLabel)
                    .accessibilityLabel("Token usage: \(usageStatusLabel)")
            }

            if let spendStatusLabel = topBar.spendStatusLabel {
                statusChip(spendStatusLabel, tint: QuillCodePalette.green)
                    .help(topBar.spendStatusDetail ?? spendStatusLabel)
                    .accessibilityLabel("Thread spend: \(spendStatusLabel)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusChip(_ label: String, tint: Color = QuillCodePalette.muted) -> some View {
        Text(label)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.10))
            )
    }

    private func tokenBudgetView(_ budget: TokenBudgetSurface) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Tokens")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .textCase(.uppercase)
                Text(budget.primaryLabel)
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(QuillCodePalette.panel.opacity(0.85))
                    Capsule()
                        .fill(tokenBudgetTint(for: budget).opacity(0.82))
                        .frame(width: proxy.size.width * CGFloat(budget.progressPercent) / 100)
                }
            }
            .frame(height: 4)

            Text(budget.secondaryLabel)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if !budget.visibleQuotaLimits.isEmpty {
                HStack(spacing: 4) {
                    ForEach(budget.visibleQuotaLimits.prefix(3), id: \.id) { quota in
                        Text(quota.compactLabel)
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(tokenBudgetTint(for: budget))
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(tokenBudgetTint(for: budget).opacity(0.12))
                            )
                    }
                }
                .lineLimit(1)
            }
        }
        .padding(.horizontal, QuillCodeMetrics.topBarTokenBudgetHorizontalPadding)
        .padding(.vertical, QuillCodeMetrics.topBarTokenBudgetVerticalPadding)
        .frame(
            minWidth: QuillCodeMetrics.topBarTokenBudgetMinWidth,
            maxWidth: QuillCodeMetrics.topBarTokenBudgetMaxWidth,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tokenBudgetTint(for: budget).opacity(0.11))
        )
    }

    private func tokenBudgetTint(for budget: TokenBudgetSurface) -> Color {
        if budget.usedPercent >= 100 { return QuillCodePalette.red }
        if budget.usedPercent >= 80 { return QuillCodePalette.yellow }
        return QuillCodePalette.blue
    }
}
