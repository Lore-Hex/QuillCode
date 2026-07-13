import SwiftUI

struct QuillCodeWorktreeSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            rootField
            Divider().opacity(0.45)
            cleanupControls
        }
        .quillCodeSettingsCard(tint: QuillCodePalette.blue)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Managed worktrees")
                    .font(.headline)
                Text(settings.managedWorktreeSummary)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Text(settings.managedWorktreeStatusLabel)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(QuillCodePalette.blue.opacity(0.16))
                .foregroundStyle(QuillCodePalette.blue)
                .clipShape(Capsule())
        }
    }

    private var rootField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Worktree root")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                TextField(settings.managedWorktreeResolvedRoot, text: $draft.managedWorktreeRootText)
                    .textFieldStyle(.roundedBorder)
                    .quillCodeTextEntryTarget()
                    .accessibilityIdentifier("quillcode-settings-worktree-root")
                Button {
                    draft.resetManagedWorktreeRoot()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .quillCodeIconButtonTarget(size: 40, radius: 9)
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .disabled(draft.managedWorktreeRootText.isEmpty)
                .help("Use the default worktree root")
                .accessibilityLabel("Use default worktree root")
            }
            Text("Leave blank to use \(settings.managedWorktreeResolvedRoot).")
                .font(.caption2)
                .foregroundStyle(QuillCodePalette.muted)
                .textSelection(.enabled)
        }
    }

    private var cleanupControls: some View {
        HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
            Toggle("Automatically remove old worktrees", isOn: $draft.automaticallyCleanManagedWorktrees)
                .toggleStyle(.switch)
                .quillCodeSwitchRowTarget()
                .accessibilityIdentifier("quillcode-settings-worktree-cleanup")
            Spacer(minLength: QuillCodeMetrics.controlClusterSpacing)
            Text("Keep")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            TextField("15", text: $draft.managedWorktreeRetentionLimitText)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .frame(width: 70)
                .quillCodeTextEntryTarget()
                .disabled(!draft.automaticallyCleanManagedWorktrees)
                .accessibilityIdentifier("quillcode-settings-worktree-retention-limit")
        }
    }
}
