import SwiftUI
import QuillCodeCore

struct QuillCodeManagedWorktreeSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: QuillCodeMetrics.controlClusterSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Worktrees")
                        .font(.headline)
                    Text(settings.managedWorktreeSummary)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Text(settings.managedWorktreeStatusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Worktree root")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.muted)
                HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                    TextField("Managed worktree directory", text: $draft.managedWorktreeRootPathText)
                        .textFieldStyle(.roundedBorder)
                        .quillCodeTextEntryTarget()
                        .accessibilityIdentifier("quillcode-settings-worktree-root")
                    Button("Use default") {
                        draft.managedWorktreeRootPathText = draft.managedWorktreeDefaultRootPath
                    }
                    .buttonStyle(QuillCodeActionButtonStyle(minWidth: 94))
                    .quillCodeFormActionTarget(minWidth: 94)
                    .disabled(draft.managedWorktreeRootPathText == draft.managedWorktreeDefaultRootPath)
                }
            }

            Toggle("Automatically clean up old managed worktrees", isOn: $draft.managedWorktreeAutomaticCleanupEnabled)
                .toggleStyle(.switch)
                .quillCodeSwitchRowTarget()
                .accessibilityIdentifier("quillcode-settings-worktree-cleanup")

            if draft.managedWorktreeAutomaticCleanupEnabled {
                Stepper(
                    value: $draft.managedWorktreeRetentionLimit,
                    in: ManagedWorktreeSettings.retentionLimitRange
                ) {
                    HStack {
                        Text("Keep recent worktrees")
                        Spacer()
                        Text("\(draft.managedWorktreeRetentionLimit)")
                            .monospacedDigit()
                            .foregroundStyle(QuillCodePalette.muted)
                    }
                }
                .quillCodeAdjustableControlTarget()
                .accessibilityIdentifier("quillcode-settings-worktree-retention")
            }

            Text("Pinned, running, selected, Local-handoff, and permanent branch worktrees are never removed automatically. Every eligible worktree is snapshotted before deletion.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .quillCodeSettingsCard(tint: QuillCodePalette.blue)
    }
}
