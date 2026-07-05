import SwiftUI

struct QuillCodeBrowserDomainSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            explanation
            domainField(
                title: "Allowed domains",
                placeholder: "trustedrouter.com\nlocalhost",
                text: $draft.browserAllowedDomainsText,
                accessibilityID: "quillcode-browser-allowed-domains"
            )
            domainField(
                title: "Blocked domains",
                placeholder: "example.test\nads.example.com",
                text: $draft.browserBlockedDomainsText,
                accessibilityID: "quillcode-browser-blocked-domains"
            )
            resetRow
        }
        .quillCodeSettingsCard(tint: policyTint)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Browser Domains")
                    .font(.headline)
                Text(settings.browserDomainPolicySummary)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer()
            Text(settings.browserDomainPolicyStatusLabel)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(policyTint.opacity(0.16))
                .foregroundStyle(policyTint)
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
    Leave allowed domains empty to allow all network pages. Blocked domains always win, including subdomains. File previews remain local and are not domain-matched.
    """

    private var policyTint: Color {
        settings.browserAllowedDomains.isEmpty && settings.browserBlockedDomains.isEmpty
            ? QuillCodePalette.yellow
            : QuillCodePalette.green
    }

    private func domainField(
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
                draft.clearBrowserDomainPolicy()
            }
            .buttonStyle(QuillCodeActionButtonStyle(minWidth: 160, alignment: .leading))
            .quillCodeFormActionTarget(minWidth: 160, alignment: .leading)
            .accessibilityIdentifier("quillcode-browser-domain-reset")
            .disabled(!hasDraftPolicy)
            Spacer()
        }
        .font(.caption.weight(.semibold))
    }

    private var hasDraftPolicy: Bool {
        !draft.browserAllowedDomainsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.browserBlockedDomainsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
