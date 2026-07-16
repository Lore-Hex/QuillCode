import SwiftUI

struct QuillCodeTrustedRouterCreditsSettingsCard: View {
    var balance: ProviderAccountBalanceSurface
    var refreshCommand: WorkspaceCommandSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: QuillCodeMetrics.controlClusterSpacing) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TrustedRouter account")
                        .font(.headline)
                    Text(balance.amountLabel ?? balance.statusLabel)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(balance.amountLabel == nil ? tint : QuillCodePalette.text)
                        .accessibilityIdentifier("quillcode-trustedrouter-balance")
                }
                .layoutPriority(1)
                Spacer()
                Text(balance.statusLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.16))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("quillcode-trustedrouter-balance-status")
            }

            Text(balance.detailLabel)
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onCommand(refreshCommand)
            } label: {
                HStack(spacing: 7) {
                    if balance.tone == .updating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Refreshing balance")
                    } else {
                        Label("Refresh balance", systemImage: "arrow.clockwise")
                    }
                }
            }
            .buttonStyle(QuillCodeActionButtonStyle(minWidth: 132, alignment: .leading))
            .quillCodeFormActionTarget(minWidth: 132, alignment: .leading)
            .disabled(!refreshCommand.isEnabled)
            .accessibilityIdentifier("quillcode-trustedrouter-balance-refresh")
        }
        .quillCodeSettingsCard(tint: tint)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(balance.accessibilityLabel)
    }

    private var tint: Color {
        balance.tone.quillCodeTint
    }
}
