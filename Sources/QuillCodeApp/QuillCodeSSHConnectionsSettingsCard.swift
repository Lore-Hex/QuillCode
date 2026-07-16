import SwiftUI

struct QuillCodeSSHConnectionsSettingsCard: View {
    var isAvailable: Bool
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Image(systemName: "network")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(QuillCodePalette.blue)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("SSH Connections")
                    .font(.callout.weight(.semibold))
                Text("Open a project on a host from ~/.ssh/config or enter an address manually.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Add remote", action: onOpen)
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 104))
                .quillCodeFormActionTarget(minWidth: 104)
                .disabled(!isAvailable)
                .accessibilityIdentifier("quillcode-settings-add-ssh-project")
        }
        .quillCodeSettingsCard(tint: QuillCodePalette.blue)
    }
}
