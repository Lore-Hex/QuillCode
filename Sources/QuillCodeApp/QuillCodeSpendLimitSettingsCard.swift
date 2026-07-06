import SwiftUI

struct QuillCodeSpendLimitSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            spendField(
                title: "Thread review fuse",
                detail: "Ask before a thread spends past this local amount.",
                placeholder: "1.00",
                text: $draft.runSpendFuseUSDText,
                accessibilityIdentifier: "quillcode-settings-run-spend-fuse"
            )
            HStack(alignment: .top, spacing: 10) {
                spendField(
                    title: "Daily cap",
                    detail: "Top-bar day row.",
                    placeholder: "5.00",
                    text: $draft.runSpendDailyLimitUSDText,
                    accessibilityIdentifier: "quillcode-settings-run-spend-daily-limit"
                )
                spendField(
                    title: "Weekly cap",
                    detail: "Top-bar week row.",
                    placeholder: "25.00",
                    text: $draft.runSpendWeeklyLimitUSDText,
                    accessibilityIdentifier: "quillcode-settings-run-spend-weekly-limit"
                )
                spendField(
                    title: "Monthly cap",
                    detail: "Top-bar month row.",
                    placeholder: "100.00",
                    text: $draft.runSpendMonthlyLimitUSDText,
                    accessibilityIdentifier: "quillcode-settings-run-spend-monthly-limit"
                )
            }
        }
        .quillCodeSettingsCard(tint: statusTint)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local spend limits")
                    .font(.headline)
                Text(settings.runSpendLimitSummary)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Text(settings.runSpendLimitStatusLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusTint.opacity(0.16))
                .foregroundStyle(statusTint)
                .clipShape(Capsule())
        }
    }

    private var statusTint: Color {
        settings.runSpendFuseUSD != nil || settings.runSpendPeriodLimits.hasAnyLimit
            ? QuillCodePalette.green
            : QuillCodePalette.yellow
    }

    private func spendField(
        title: String,
        detail: String,
        placeholder: String,
        text: Binding<String>,
        accessibilityIdentifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .quillCodeTextEntryTarget()
                .accessibilityIdentifier(accessibilityIdentifier)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
