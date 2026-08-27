import SwiftUI

/// Keeps connection recovery visible without replacing a returning user's saved transcript.
struct QuillCodeConnectBannerView: View {
    var onSignIn: () -> Void
    var onUseDeveloperKey: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                message
                Spacer(minLength: 12)
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                message
                actions
            }
        }
        .padding(14)
        .background(QuillCodePalette.panel2)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(QuillCodePalette.yellow.opacity(0.48), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TrustedRouter connection required")
    }

    private var message: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.yellow)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(TranscriptConnectPrompt.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(QuillCodePalette.text)
                Text(TranscriptConnectPrompt.returningUserSubtitle)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button("Sign in", action: onSignIn)
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 240))
                .quillCodeFormActionTarget(minWidth: 240)
                .accessibilityIdentifier("quillcode-connect-sign-in")
            Button(action: onUseDeveloperKey) {
                Label(TranscriptConnectPrompt.developerKeyTitle, systemImage: "key.fill")
            }
            .buttonStyle(QuillCodeActionButtonStyle(.secondary, minWidth: 240))
            .quillCodeFormActionTarget(minWidth: 240)
            .accessibilityIdentifier("quillcode-connect-developer-key")
            .help("Open API key settings")
        }
        .frame(width: 240)
    }
}
