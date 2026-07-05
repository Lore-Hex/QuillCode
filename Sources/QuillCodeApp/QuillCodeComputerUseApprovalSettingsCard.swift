import SwiftUI
import QuillComputerUseKit

struct QuillCodeComputerUseApprovalSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            explanation
            detectedAppRow
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
        .quillCodeSettingsCard(tint: approvalTint)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
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
            .padding(9)
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

    @ViewBuilder
    private var detectedAppRow: some View {
        if let application = settings.computerUseForegroundApplication {
            let alreadyApproved = draft.hasComputerUseApproval(for: application)
            HStack(alignment: .center, spacing: QuillCodeMetrics.controlClusterSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected foreground app")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    Text(application.displayLabel)
                        .font(.callout.weight(.semibold))
                    Text(Self.approvalTargetDescription(for: application))
                        .font(.caption2.monospaced())
                        .foregroundStyle(QuillCodePalette.muted)
                        .lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Button(alreadyApproved ? "Already allowed" : "Allow Current App") {
                    draft.addComputerUseApproval(for: application)
                }
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 152))
                .quillCodeFormActionTarget(minWidth: 152)
                .disabled(alreadyApproved)
                .accessibilityIdentifier("quillcode-computer-use-allow-current-app")
            }
            .padding(9)
            .background(QuillCodePalette.background.opacity(0.48))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Text("No foreground app detected yet. Focus an app, then refresh Computer Use status.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(QuillCodePalette.background.opacity(0.36))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private static func approvalTargetDescription(for application: ComputerUseApplication) -> String {
        if let bundleIdentifier = application.bundleIdentifier {
            return "Will save bundle ID: \(bundleIdentifier)"
        }
        if let name = application.name {
            return "Will save app name: \(name)"
        }
        return "No stable app identifier available"
    }

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
