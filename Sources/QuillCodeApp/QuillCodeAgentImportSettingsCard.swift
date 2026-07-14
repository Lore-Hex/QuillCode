import SwiftUI

struct QuillCodeAgentImportSettingsCard: View {
    var isAvailable: Bool
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(QuillCodePalette.blue)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import from another agent")
                        .font(.callout.weight(.semibold))
                    Text("Bring your projects, recent chats, instructions, and extensions into QuillCode.")
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Review import", action: onOpen)
                    .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 112))
                    .quillCodeFormActionTarget(minWidth: 112)
                    .disabled(!isAvailable)
            }
            Text("Existing QuillCode files are never replaced. Credentials and provider-specific secrets must be configured again.")
                .font(.caption2)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .quillCodeSettingsCard(tint: QuillCodePalette.blue)
    }
}
