import SwiftUI

struct QuillCodeTopBarIdentityView: View {
    var topBar: TopBarSurface

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .leading, spacing: 1) {
                Text(topBar.primaryTitle)
                    .font(.system(size: 15, weight: .semibold))
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

            if let goal = topBar.goal {
                statusChip(goal.label, tint: goalTint(goal.tone))
                    .help(goal.detail)
                    .accessibilityLabel(goal.detail)
            }

            if let liveWork = topBar.liveWork {
                statusChip(
                    liveWork.label,
                    tint: liveWork.tone == .review ? QuillCodePalette.yellow : QuillCodePalette.blue
                )
                .help(liveWork.detail)
                .accessibilityLabel(liveWork.detail)
            }

            if let worktreeStatusLabel = topBar.worktreeStatusLabel {
                statusChip(
                    worktreeStatusLabel,
                    tint: topBar.worktreeStatusIsWarning ? QuillCodePalette.yellow : QuillCodePalette.blue
                )
                .help(topBar.worktreeStatusDetail ?? worktreeStatusLabel)
                .accessibilityLabel(topBar.worktreeStatusDetail ?? worktreeStatusLabel)
            }

            if let tokenBudget = topBar.tokenBudget {
                tokenBudgetView(tokenBudget)
                    .accessibilityLabel(tokenBudget.accessibilityLabel)
                    .layoutPriority(1)
            } else if topBar.spendStatusLabel == nil,
                      let usageStatusLabel = topBar.usageStatusLabel {
                statusChip(usageStatusLabel)
                    .help(usageStatusLabel)
                    .accessibilityLabel("Token usage: \(usageStatusLabel)")
            }

            if let accountBalance = topBar.accountBalance {
                statusChip(
                    accountBalance.compactLabel,
                    tint: accountBalance.tone.quillCodeTint
                )
                .help(accountBalance.detailLabel)
                .accessibilityLabel(accountBalance.accessibilityLabel)
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
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
    }

    /// The context chip stays SHORT on purpose: "Context 70.4k / 200k" plus a small meter. Remaining,
    /// percent, arrows, source, and quota periods all live in the tooltip — inlining them starved the
    /// thread title and truncated every element at real window widths.
    private func tokenBudgetView(_ budget: TokenBudgetSurface) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("Context")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(QuillCodePalette.muted)
            Text(budget.primaryLabel)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(1)
                .fixedSize()
            tokenBudgetProgressBar(budget)
                .frame(width: 64, height: 4)
                .alignmentGuide(.firstTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center]
                }
        }
        .padding(.horizontal, QuillCodeMetrics.topBarTokenBudgetHorizontalPadding)
        .padding(.vertical, QuillCodeMetrics.topBarTokenBudgetVerticalPadding)
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokenBudgetTint(for: budget).opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(QuillCodePalette.line, lineWidth: 1)
                )
        )
        .help(tokenBudgetHelp(budget))
    }

    /// Everything the slim chip no longer shows inline: full numbers, remaining, percent, source,
    /// and local spend periods — one hover away.
    private func tokenBudgetHelp(_ budget: TokenBudgetSurface) -> String {
        var lines = [
            "Context window for this conversation — \(budget.secondaryLabel).",
            budget.detailLabel,
            "This is how much the model can \"remember\" at once, not a spending limit. "
            + "When it fills, the oldest messages are trimmed to make room."
        ]
        if let quotaSummaryLabel = budget.quotaSummaryLabel {
            lines.insert("Local spend: \(quotaSummaryLabel)", at: 2)
        }
        return lines.joined(separator: "\n")
    }

    private func tokenBudgetProgressBar(_ budget: TokenBudgetSurface) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(QuillCodePalette.panel.opacity(0.86))
                Capsule()
                    .fill(tokenBudgetTint(for: budget).opacity(0.86))
                    .frame(width: proxy.size.width * CGFloat(budget.progressPercent) / 100)
            }
        }
    }

    private func tokenBudgetTint(for budget: TokenBudgetSurface) -> Color {
        if budget.usedPercent >= 100 { return QuillCodePalette.red }
        if budget.usedPercent >= 80 { return QuillCodePalette.yellow }
        return QuillCodePalette.blue
    }

    private func goalTint(_ tone: TopBarGoalTone) -> Color {
        switch tone {
        case .active: QuillCodePalette.blue
        case .blocked: QuillCodePalette.yellow
        case .completed: QuillCodePalette.green
        }
    }
}
