import SwiftUI

struct QuillCodeTopBarIdentityView: View {
    var topBar: TopBarSurface

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(topBar.primaryTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(topBar.subtitle)
                    .font(.system(size: 12.5, weight: .medium))
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
            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(0.10))
            )
    }

    private func tokenBudgetView(_ budget: TokenBudgetSurface) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Context")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                Text(budget.primaryLabel)
                    .font(.system(size: 14.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(QuillCodePalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.94)
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
            .frame(height: 3)

            HStack(spacing: 6) {
                Text(budget.secondaryLabel)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(QuillCodePalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.94)

                if !budget.visibleQuotaLimits.isEmpty {
                    Text(budget.visibleQuotaLimits.prefix(2).map(\.compactLabel).joined(separator: " · "))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(tokenBudgetTint(for: budget))
                        .lineLimit(1)
                        .minimumScaleFactor(0.94)
                }
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
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(tokenBudgetTint(for: budget).opacity(0.11))
        )
    }

    private func tokenBudgetTint(for budget: TokenBudgetSurface) -> Color {
        if budget.usedPercent >= 100 { return QuillCodePalette.red }
        if budget.usedPercent >= 80 { return QuillCodePalette.yellow }
        return QuillCodePalette.blue
    }
}
