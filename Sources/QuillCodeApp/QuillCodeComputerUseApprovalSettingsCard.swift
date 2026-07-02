import SwiftUI

struct QuillCodeComputerUseApprovalSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            explanation
            approvalField(
                title: "Bundle identifiers",
                placeholder: "com.apple.Terminal\ncom.google.Chrome",
                text: $draft.computerUseApprovedBundleIdentifiersText,
                accessibilityID: "quillcode-computer-use-approved-bundles"
            )
            approvalField(
                title: "App names",
                placeholder: "Terminal\nGoogle Chrome",
                text: $draft.computerUseApprovedAppNamesText,
                accessibilityID: "quillcode-computer-use-approved-app-names"
            )
            resetRow
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
                Text("Approved Apps")
                    .font(.headline)
                Text(settings.computerUseApprovalSummary)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Text(settings.computerUseApprovalStatusLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(approvalTint.opacity(0.16))
                .foregroundStyle(approvalTint)
                .clipShape(Capsule())
        }
    }

    private var explanation: some View {
        Text(Self.explanationText)
            .font(.caption)
            .foregroundStyle(QuillCodePalette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QuillCodePalette.background.opacity(0.48))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private static let explanationText = """
    Leave both lists empty for unrestricted Computer Use. Add bundle IDs for precise macOS approval, or app names for cross-platform fallback.
    """

    private var approvalTint: Color {
        settings.computerUseApprovedBundleIdentifiers.isEmpty && settings.computerUseApprovedAppNames.isEmpty
            ? QuillCodePalette.yellow
            : QuillCodePalette.green
    }

    private func approvalField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        accessibilityID: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .quillCodeTextEntryTarget(minHeight: 88, alignment: .topLeading)
                .accessibilityIdentifier(accessibilityID)
        }
    }

    private var resetRow: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Button("Reset to unrestricted") {
                draft.clearComputerUseApprovals()
            }
            .buttonStyle(QuillCodeActionButtonStyle(minWidth: 160, alignment: .leading))
            .quillCodeFormActionTarget(minWidth: 160, alignment: .leading)
            Spacer()
        }
        .font(.caption.weight(.semibold))
    }
}
