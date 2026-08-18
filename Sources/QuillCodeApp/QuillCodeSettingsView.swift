import SwiftUI
import QuillCodeCore

struct QuillCodeSettingsView: View {
    var settings: WorkspaceSettingsSurface
    @Binding var draft: QuillCodeSettingsDraft
    var onCancel: () -> Void
    var onSave: () -> Void
    var onStartTrustedRouterSignIn: () -> Void
    var onOpenAgentImport: (() -> Void)?
    var onOpenSSHConnection: (() -> Void)?
    var onCommand: (WorkspaceCommandSurface) -> Void
    @State private var selectedSection = QuillCodeSettingsSection.account

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

            Divider().opacity(0.5)

            HStack(spacing: 0) {
                settingsNavigation

                Divider().opacity(0.5)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text(selectedSection.title)
                            .font(.title3.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("quillcode-settings-section-title")
                        selectedSectionContent

                        if let issue = settings.runtimeIssue {
                            QuillCodeRuntimeIssueView(issue: issue, showsDiagnostics: true)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            Divider().opacity(0.5)
            settingsFooter
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(
            minWidth: 560,
            idealWidth: 720,
            maxWidth: 720,
            minHeight: 480,
            idealHeight: 680,
            maxHeight: 720
        )
        .background(QuillCodePalette.background)
    }

    private var settingsNavigation: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(QuillCodeSettingsSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.callout.weight(selectedSection == section ? .semibold : .regular))
                        .foregroundStyle(
                            selectedSection == section ? QuillCodePalette.text : QuillCodePalette.body
                        )
                        .padding(.horizontal, 12)
                        .quillCodeFullRowButtonTarget(minHeight: 40, radius: 0)
                        .background(
                            selectedSection == section
                                ? QuillCodePalette.selection
                                : Color.clear
                        )
                }
                .buttonStyle(QuillCodePressableButtonStyle())
                .accessibilityIdentifier("quillcode-settings-section-\(section.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .frame(width: 154)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(QuillCodePalette.sidebar)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .account:
            authenticationSection
            if let balance = settings.trustedRouterAccountBalance {
                QuillCodeTrustedRouterCreditsSettingsCard(
                    balance: balance,
                    refreshCommand: settings.trustedRouterCreditsRefreshCommand,
                    onCommand: onCommand
                )
            }
            QuillCodeSpendLimitSettingsCard(settings: settings, draft: $draft)
        case .general:
            QuillCodeNotificationSettingsCard(settings: settings, draft: $draft)
            QuillCodeCodeReviewSettingsCard(draft: $draft)
            QuillCodePersonalitySettingsCard(draft: $draft)
            QuillCodeManagedWorktreeSettingsCard(settings: settings, draft: $draft)
        case .permissions:
            QuillCodeComputerUseSettingsCard(settings: settings, onCommand: onCommand)
            QuillCodeComputerUseApprovalSettingsCard(settings: settings, draft: $draft)
        case .connections:
            QuillCodeBrowserDomainSettingsCard(settings: settings, draft: $draft)
            QuillCodeSSHConnectionsSettingsCard(
                isAvailable: onOpenSSHConnection != nil,
                onOpen: { onOpenSSHConnection?() }
            )
            QuillCodeAgentImportSettingsCard(
                isAvailable: onOpenAgentImport != nil,
                onOpen: { onOpenAgentImport?() }
            )
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: QuillCodeMetrics.controlClusterSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.custom("Iowan Old Style", size: 24).weight(.semibold))
                    .accessibilityIdentifier("quillcode-settings-title")
                Text(QuillCodeProduct.fullBrandName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(QuillCodePalette.body)
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
                .overlay(
                    RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                        .stroke(
                            (settings.hasStoredAPIKey ? QuillCodePalette.green : QuillCodePalette.yellow).opacity(0.35),
                            lineWidth: 1
                        )
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: QuillCodeMetrics.compactControlRadius, style: .continuous)
                )
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(QuillCodePalette.muted)
                    .quillCodeIconButtonTarget(size: 36, radius: QuillCodeMetrics.iconControlRadius)
                    .background(QuillCodePalette.selection.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: QuillCodeMetrics.iconControlRadius, style: .continuous)
                            .stroke(QuillCodePalette.line, lineWidth: 1)
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: QuillCodeMetrics.iconControlRadius, style: .continuous)
                    )
            }
            .buttonStyle(QuillCodePressableButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close settings")
            .accessibilityLabel("Close settings")
            .accessibilityIdentifier("quillcode-settings-close")
        }
    }

    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.distribution.requiresConfidentialRouting {
                confidentialAuthenticationSection
            } else {
                authenticationPicker
                apiBaseURLField
                authenticationDetail
            }
        }
        .quillCodeSettingsCard(tint: draft.authMode == .oauth ? QuillCodePalette.blue : QuillCodePalette.yellow)
    }

    private var confidentialAuthenticationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Confidential routing required", systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(QuillCodePalette.green)
            Text("Every model, safety review, summary, and model-assisted search request is restricted to confidential providers. Requests fail closed instead of falling back to a standard route.")
                .font(.callout)
                .foregroundStyle(QuillCodePalette.body)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Processing region", selection: $draft.confidentialJurisdiction) {
                ForEach(TrustedRouterJurisdiction.allCases) { jurisdiction in
                    Text(jurisdiction.displayName).tag(jurisdiction)
                }
            }
            .pickerStyle(.segmented)
            .quillCodeSegmentedControlTarget()
            .accessibilityIdentifier("quillcode-settings-confidential-jurisdiction")
            oauthLoginSection
        }
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
                .textFieldStyle(QuillCodeTextFieldStyle())
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
            Text(settings.distribution.requiresConfidentialRouting
                ? "TrustedRouter login returns through \(QuillCodeProduct.displayName)'s local callback. Routing policy cannot be disabled in this edition."
                : "OAuth browser login opens TrustedRouter and returns through \(QuillCodeProduct.displayName)'s local callback. Developer keys stay hidden unless you switch modes.")
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
                .textFieldStyle(QuillCodeTextFieldStyle())
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

private enum QuillCodeSettingsSection: String, CaseIterable, Identifiable {
    case account
    case general
    case permissions
    case connections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: "Account"
        case .general: "General"
        case .permissions: "Permissions"
        case .connections: "Connections"
        }
    }

    var systemImage: String {
        switch self {
        case .account: "person.crop.circle"
        case .general: "slider.horizontal.3"
        case .permissions: "hand.raised"
        case .connections: "point.3.connected.trianglepath.dotted"
        }
    }
}
