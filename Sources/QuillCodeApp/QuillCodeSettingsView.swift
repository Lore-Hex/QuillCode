import SwiftUI
import QuillCodeCore

struct QuillCodeSettingsView: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft
    var onCancel: () -> Void
    var onSave: () -> Void
    var onStartTrustedRouterSignIn: () -> Void
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsHeader
                QuillCodeComputerUseSettingsCard(settings: settings, onCommand: onCommand)

                Divider()

                if let issue = settings.runtimeIssue {
                    QuillCodeRuntimeIssueView(issue: issue, showsDiagnostics: true)
                }

                authenticationPicker
                apiBaseURLField
                authenticationDetail
                settingsFooter
            }
            .padding(24)
        }
        .frame(width: 560)
        .frame(maxHeight: 720)
    }

    private var settingsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Text(settings.loginStatusLabel)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
            }
            Spacer()
            Text(settings.apiKeyStatusLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow).opacity(0.16))
                .foregroundStyle(settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow)
                .clipShape(Capsule())
        }
    }

    private var authenticationPicker: some View {
        Picker("Authentication", selection: $draft.authMode) {
            Text("TrustedRouter login").tag(TrustedRouterAuthMode.oauth)
            Text("Developer override").tag(TrustedRouterAuthMode.developerOverride)
        }
        .pickerStyle(.segmented)
        .onChange(of: draft.authMode) { _, mode in
            draft.developerOverrideEnabled = mode == .developerOverride
        }
    }

    private var apiBaseURLField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TrustedRouter API base URL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            TextField("https://api.trustedrouter.com/v1", text: $draft.apiBaseURL)
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var authenticationDetail: some View {
        if draft.authMode == .oauth {
            oauthLoginSection
        } else {
            developerOverrideSection
        }
    }

    private var oauthLoginSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OAuth browser login opens TrustedRouter and returns through QuillCode's local callback. Developer keys stay hidden unless you switch modes.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
            Button("Sign in with TrustedRouter", action: onStartTrustedRouterSignIn)
                .buttonStyle(.borderedProminent)
                .quillCodeHitTarget(minWidth: 190)
            Text(settings.signInURL)
                .font(.caption2.monospaced())
                .foregroundStyle(QuillCodePalette.muted)
                .textSelection(.enabled)
        }
    }

    private var developerOverrideSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Replace API key")
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuillCodePalette.muted)
            SecureField(settings.hasStoredAPIKey ? "Leave blank to keep saved key" : "Paste TrustedRouter key", text: $draft.replacementAPIKey)
                .textFieldStyle(.roundedBorder)
            if draft.shouldClearAPIKey {
                Text("Saved key will be cleared when you save.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.yellow)
            }
            Button("Clear API key") {
                draft.replacementAPIKey = ""
                draft.shouldClearAPIKey = true
            }
            .disabled(!settings.hasStoredAPIKey)
            .font(.caption)
            .quillCodeHitTarget(minWidth: 104, alignment: .leading)
        }
    }

    private var settingsFooter: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .quillCodeHitTarget(minWidth: 72)
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .quillCodeHitTarget(minWidth: 72)
                .disabled(!draft.canSave)
        }
    }
}
