import SwiftUI

/// First-run "connect your account" hero, shown in place of the project starter cards when the app has
/// no TrustedRouter credential. It surfaces the existing OAuth action and routes developer-key users
/// into the existing Settings flow, so credential storage still has one owner. See
/// ``TranscriptConnectPrompt`` for the show/hide decision and copy.
struct QuillCodeConnectView: View {
    var prompt: TranscriptConnectPrompt
    var onSignIn: () -> Void
    var onUseDeveloperKey: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(QuillCodePalette.blue.opacity(0.14))
                    .frame(width: 60, height: 60)
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(QuillCodePalette.blue)
            }
            .accessibilityHidden(true)

            Text(TranscriptConnectPrompt.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuillCodePalette.text)

            Text(TranscriptConnectPrompt.subtitle)
                .font(.callout)
                .lineSpacing(3)
                .foregroundStyle(QuillCodePalette.muted)

            Button(TranscriptConnectPrompt.signInButtonTitle, action: onSignIn)
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 240))
                .quillCodeFormActionTarget(minWidth: 240)
                .accessibilityIdentifier("quillcode-connect-sign-in")
                .padding(.top, 2)

            Label(TranscriptConnectPrompt.browserSignInCaption, systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)

            Button(action: onUseDeveloperKey) {
                Label(TranscriptConnectPrompt.developerKeyTitle, systemImage: "key.fill")
            }
            .buttonStyle(QuillCodeActionButtonStyle(.secondary, minWidth: 240))
            .quillCodeFormActionTarget(minWidth: 240)
            .accessibilityIdentifier("quillcode-connect-developer-key")
            .help("Open API key settings")

            if let accountURL = URL(string: prompt.accountURL) {
                Link(destination: accountURL) {
                    Text(TranscriptConnectPrompt.createAccountTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(QuillCodePalette.blue)
                        .quillCodeLinkTarget()
                }
                .accessibilityIdentifier("quillcode-connect-create-account")
            }

            stepsRow
                .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    private var stepsRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(TranscriptConnectPrompt.steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(QuillCodePalette.line)
                }
                Text("\(index + 1) \(step)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(index == 0 ? QuillCodePalette.blue : QuillCodePalette.muted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Steps: connect, choose a model, start a task")
    }
}
