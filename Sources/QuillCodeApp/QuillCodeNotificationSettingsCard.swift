import SwiftUI

struct QuillCodeNotificationSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Toggle(isOn: $draft.agentRunNotificationsEnabled) {
                toggleLabel(
                    title: "Agent run alerts",
                    detail: "Notify when a background run finishes, fails, or needs approval."
                )
            }
            .toggleStyle(.switch)
            .quillCodeSwitchRowTarget()
            .accessibilityIdentifier("quillcode-notifications-agent-runs")

            Toggle(isOn: $draft.agentRunNotificationsOnlyWhenInactive) {
                toggleLabel(
                    title: "Only when inactive",
                    detail: "Skip run alerts while QuillCode is already frontmost."
                )
            }
            .toggleStyle(.switch)
            .quillCodeSwitchRowTarget()
            .accessibilityIdentifier("quillcode-notifications-only-when-inactive")
            .disabled(!draft.agentRunNotificationsEnabled)
            .opacity(draft.agentRunNotificationsEnabled ? 1 : 0.56)

            Toggle(isOn: $draft.automationNotificationsEnabled) {
                toggleLabel(
                    title: "Automation alerts",
                    detail: "Notify when scheduled work creates a follow-up thread."
                )
            }
            .toggleStyle(.switch)
            .quillCodeSwitchRowTarget()
            .accessibilityIdentifier("quillcode-notifications-automations")
        }
        .padding(14)
        .background(QuillCodePalette.panel.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(QuillCodePalette.blue.opacity(0.20), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 7)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications")
                    .font(.headline)
                Text(settings.notificationSummary)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Text(settings.notificationStatusLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusTint.opacity(0.16))
                .foregroundStyle(statusTint)
                .clipShape(Capsule())
        }
    }

    private var statusTint: Color {
        settings.notificationPreferences.anyNotificationEnabled
            ? QuillCodePalette.green
            : QuillCodePalette.yellow
    }

    private func toggleLabel(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
