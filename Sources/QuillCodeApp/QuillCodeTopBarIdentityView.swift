import SwiftUI
import QuillCodeCore

struct QuillCodeTopBarIdentityView: View {
    var topBar: TopBarSurface
    var onSetSpendLimit: (Double?) -> Void = { _ in }
    @State private var showsKeyUsageDetails = false
    @State private var showsSpendLimitDetails = false

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Text(topBar.primaryTitle)
                .font(.custom("Iowan Old Style", size: 16).weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .truncationMode(.tail)
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
                Button {
                    showsKeyUsageDetails.toggle()
                } label: {
                    HStack(spacing: 4) {
                        statusChip(
                            accountBalance.compactLabel,
                            tint: accountBalance.tone.quillCodeTint
                        )
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(accountBalance.tone.quillCodeTint)
                    }
                    .contentShape(Rectangle())
                    .fixedSize(horizontal: true, vertical: false)
                }
                .quillCodeCapsuleButtonTarget()
                .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
                .layoutPriority(2)
                .help("Show TrustedRouter key usage and limits")
                .accessibilityLabel(accountBalance.accessibilityLabel)
                .accessibilityHint("Shows daily, weekly, monthly, and total key usage")
                .popover(isPresented: $showsKeyUsageDetails, arrowEdge: .bottom) {
                    keyUsagePopover(accountBalance)
                }
            }

            if let spendStatusLabel = topBar.spendStatusLabel {
                Button {
                    showsSpendLimitDetails.toggle()
                } label: {
                    HStack(spacing: 4) {
                        statusChip(spendStatusLabel, tint: QuillCodePalette.green)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(QuillCodePalette.green)
                    }
                    .contentShape(Rectangle())
                    .fixedSize(horizontal: true, vertical: false)
                }
                .quillCodeCapsuleButtonTarget()
                .buttonStyle(QuillCodePressableButtonStyle(enforcesMinimumHitTarget: false))
                .layoutPriority(2)
                .help("Adjust this task's limit")
                .accessibilityLabel(spendStatusLabel)
                .accessibilityHint("Shows controls to increase or decrease this task's limit")
                .accessibilityIdentifier("quillcode-topbar-spend-limit")
                .popover(isPresented: $showsSpendLimitDetails, arrowEdge: .bottom) {
                    spendLimitPopover(
                        spentUSD: topBar.threadSpendUSD ?? 0,
                        limitUSD: topBar.runSpendLimitUSD
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusChip(_ label: String, tint: Color = QuillCodePalette.muted) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
            .overlay {
                RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                    .stroke(tint.opacity(0.32), lineWidth: 1)
            }
    }

    private func keyUsagePopover(_ balance: ProviderAccountBalanceSurface) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("TrustedRouter limits")
                    .font(.headline)
                Spacer()
                Text(balance.statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(balance.tone.quillCodeTint)
            }
            if !balance.visibleLimits.isEmpty {
                QuillCodeTrustedRouterKeyLimitsView(limits: balance.visibleLimits)
            }
            Text(balance.detailLabel)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 340)
        .background(QuillCodePalette.background)
    }

    private func spendLimitPopover(spentUSD: Double, limitUSD: Double?) -> some View {
        let lowerLimit = SpendLimitAdjustment.decreasedLimit(
            current: limitUSD,
            spentUSD: spentUSD
        )
        let higherLimit = SpendLimitAdjustment.increasedLimit(
            current: limitUSD,
            spentUSD: spentUSD
        )
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Task Limit")
                    .font(.headline)
                Text("Current task: \(RunSpendLedger.costLabel(spentUSD))")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
            }

            HStack(spacing: 10) {
                spendLimitAdjustmentButton(
                    systemName: "minus",
                    label: "Decrease task limit",
                    isEnabled: lowerLimit != nil
                ) {
                    onSetSpendLimit(lowerLimit)
                }

                VStack(spacing: 2) {
                    Text(limitUSD.map { RunSpendLedger.costLabel($0) } ?? "No limit")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(QuillCodePalette.text)
                    Text("per task")
                        .font(.caption2)
                        .foregroundStyle(QuillCodePalette.muted)
                }
                .frame(maxWidth: .infinity)

                spendLimitAdjustmentButton(
                    systemName: "plus",
                    label: "Increase task limit",
                    isEnabled: true
                ) {
                    onSetSpendLimit(higherLimit)
                }
            }

            Text("\(QuillCodeProduct.displayName) asks before the next paid model call after this task reaches the limit.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            if limitUSD != nil {
                Button("Remove limit") {
                    onSetSpendLimit(nil)
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .foregroundStyle(QuillCodePalette.muted)
                .quillCodeTextButtonTarget(minWidth: 104)
                .accessibilityIdentifier("quillcode-spend-limit-remove")
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(QuillCodePalette.background)
    }

    private func spendLimitAdjustmentButton(
        systemName: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(QuillCodePalette.green)
        }
        .buttonStyle(QuillCodePressableButtonStyle())
        .quillCodeIconButtonTarget()
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier("quillcode-spend-limit-\(systemName)")
    }

    /// The context chip stays SHORT on purpose: "Context 70.4k / 200k" plus a small meter. Remaining,
    /// percent, arrows, source, and quota periods all live in the tooltip — inlining them starved the
    /// thread title and truncated every element at real window widths.
    private func tokenBudgetView(_ budget: TokenBudgetSurface) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("Context")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(QuillCodePalette.muted)
            Text(budget.primaryLabel)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
            RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                .fill(tokenBudgetTint(for: budget).opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
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
                Rectangle()
                    .fill(QuillCodePalette.panel.opacity(0.86))
                Rectangle()
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
