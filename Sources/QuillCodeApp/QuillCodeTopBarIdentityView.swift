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
                    .help(tokenBudget.detailLabel)
                    .accessibilityLabel(tokenBudget.detailLabel)
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
        VStack(alignment: .leading, spacing: 5) {
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: 210, maxWidth: 260, alignment: .leading)
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
