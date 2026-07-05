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
        VStack(spacing: 0) {
            settingsHeader
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    QuillCodeNotificationSettingsCard(settings: settings, draft: $draft)
                    QuillCodeComputerUseSettingsCard(settings: settings, onCommand: onCommand)
                    QuillCodeComputerUseApprovalSettingsCard(settings: settings, draft: $draft)
                    QuillCodeBrowserDomainSettingsCard(settings: settings, draft: $draft)

                    if let issue = settings.runtimeIssue {
                        QuillCodeRuntimeIssueView(issue: issue, showsDiagnostics: true)
                    }

                    authenticationSection
                }
                .padding(20)
            }

            Divider().opacity(0.5)
            settingsFooter
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(width: 560)
        .frame(maxHeight: 720)
        .background(QuillCodePalette.background)
    }

    private var settingsHeader: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Text(settings.loginStatusLabel)
                    .font(.callout)
                    .foregroundStyle(QuillCodePalette.muted)
                Text(settings.modelCatalogStatusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(QuillCodePalette.blue)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(settings.modelCatalogStatusDetail ?? settings.modelCatalogStatusLabel)
                if let healthLabel = settings.modelProviderHealthLabel {
                    Text(healthLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(settings.modelProviderHealthDetail ?? healthLabel)
                }
            }
            Spacer()
            Text(settings.apiKeyStatusLabel)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow).opacity(0.16))
                .foregroundStyle(settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow)
                .clipShape(Capsule())
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .quillCodeIconButtonTarget(size: 36, radius: 9)
                    .background(QuillCodePalette.selection.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close settings")
            .accessibilityLabel("Close settings")
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            authenticationPicker
            apiBaseURLField
            authenticationDetail
        }
        .quillCodeSettingsCard(tint: draft.authMode == .oauth ? QuillCodePalette.blue : QuillCodePalette.yellow)
    }

    private var authenticationPicker: some View {
        Picker("Authentication", selection: $draft.authMode) {
            Text("TrustedRouter login").tag(TrustedRouterAuthMode.oauth)
            Text("Developer override").tag(TrustedRouterAuthMode.developerOverride)
        }
        .pickerStyle(.segmented)
        .quillCodeSegmentedControlTarget()
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
                .quillCodeTextEntryTarget()
                .accessibilityIdentifier("quillcode-settings-api-base-url")
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
                .buttonStyle(QuillCodeActionButtonStyle(.primary, minWidth: 190))
                .quillCodeFormActionTarget(minWidth: 190)
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
                .quillCodeTextEntryTarget()
                .accessibilityIdentifier("quillcode-settings-api-key")
            if draft.shouldClearAPIKey {
                Text("Saved key will be cleared when you save.")
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.yellow)
            }
            Button("Clear API key") {
                draft.replacementAPIKey = ""
                draft.shouldClearAPIKey = true
            }
            .buttonStyle(QuillCodeActionButtonStyle(.destructive, minWidth: 104, alignment: .leading))
            .quillCodeFormActionTarget(minWidth: 104, alignment: .leading)
            .disabled(!settings.hasStoredAPIKey)
            .font(.caption)
        }
    }

    private var settingsFooter: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            Text("Click outside this panel to close without saving.")
                .font(.caption)
                .foregroundStyle(QuillCodePalette.muted)
                .lineLimit(1)
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(QuillCodeActionButtonStyle())
                .quillCodeFormActionTarget()
            Button("Save", action: onSave)
                .buttonStyle(QuillCodeActionButtonStyle(.primary))
                .quillCodeFormActionTarget()
                .disabled(!draft.canSave)
        }
    }
}
