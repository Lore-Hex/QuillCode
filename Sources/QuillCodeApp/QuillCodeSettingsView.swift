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

                QuillCodeComputerUseSettingsCard(settings: settings, onCommand: onCommand)

                Divider()

                if let issue = settings.runtimeIssue {
                    QuillCodeRuntimeIssueView(issue: issue, showsDiagnostics: true)
                }

                Picker("Authentication", selection: $draft.authMode) {
                    Text("TrustedRouter login").tag(TrustedRouterAuthMode.oauth)
                    Text("Developer override").tag(TrustedRouterAuthMode.developerOverride)
                }
                .pickerStyle(.segmented)
                .onChange(of: draft.authMode) { _, mode in
                    draft.developerOverrideEnabled = mode == .developerOverride
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("TrustedRouter API base URL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuillCodePalette.muted)
                    TextField("https://api.trustedrouter.com/v1", text: $draft.apiBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                if draft.authMode == .oauth {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("OAuth browser login opens TrustedRouter and returns through QuillCode's local callback. Developer keys stay hidden unless you switch modes.")
                            .font(.caption)
                            .foregroundStyle(QuillCodePalette.muted)
                        Button("Sign in with TrustedRouter", action: onStartTrustedRouterSignIn)
                            .buttonStyle(.borderedProminent)
                        Text(settings.signInURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(QuillCodePalette.muted)
                            .textSelection(.enabled)
                    }
                } else {
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
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.canSave)
                }
            }
            .padding(24)
        }
        .frame(width: 560)
        .frame(maxHeight: 720)
    }
}

private struct QuillCodeComputerUseSettingsCard: View {
    var settings: WorkspaceSettingsSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Computer Use")
                        .font(.headline)
                    Text(settings.computerUseSetupSummary)
                        .font(.caption)
                        .foregroundStyle(QuillCodePalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                Spacer()
                Text(settings.computerUseStatusLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusTint.opacity(0.16))
                    .foregroundStyle(statusTint)
                    .clipShape(Capsule())
            }

            VStack(spacing: 8) {
                ForEach(settings.computerUseRequirements) { requirement in
                    QuillCodePermissionRow(requirement: requirement, onCommand: onCommand)
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: settings.computerUseStatus.available ? "checkmark.circle.fill" : "arrow.forward.circle.fill")
                    .foregroundStyle(settings.computerUseStatus.available ? QuillCodePalette.green : QuillCodePalette.blue)
                    .frame(width: 18)
                Text(settings.computerUseNextAction)
                    .font(.caption)
                    .foregroundStyle(settings.computerUseStatus.available ? QuillCodePalette.green : QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(QuillCodePalette.background.opacity(0.48))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(QuillCodePalette.blue)
                    .frame(width: 18)
                Text("After changing macOS permissions, quit and reopen QuillCode if the status does not update.")
                    .font(.caption2)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Refresh status") {
                    onCommand(settings.computerUseRefreshCommand)
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .background(QuillCodePalette.panel.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(statusTint.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
    }

    private var statusTint: Color {
        settings.computerUseStatus.available ? QuillCodePalette.green : QuillCodePalette.yellow
    }
}

private struct QuillCodePermissionRow: View {
    var requirement: ComputerUseRequirementSurface
    var onCommand: (WorkspaceCommandSurface) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.14))
                Image(systemName: requirement.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(iconTint)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(requirement.title)
                    .font(.callout.weight(.semibold))
                Text(requirement.detail)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            if requirement.isGranted {
                Text(requirement.statusLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(QuillCodePalette.green)
            } else {
                Button("Open") {
                    onCommand(requirement.command)
                }
                .buttonStyle(.bordered)
                .disabled(!requirement.command.isEnabled)
                .controlSize(.small)
                .frame(minWidth: 72, minHeight: 40)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.16))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var iconTint: Color {
        requirement.isGranted ? QuillCodePalette.green : QuillCodePalette.yellow
    }
}

struct QuillCodeRuntimeIssueView: View {
    var issue: RuntimeIssueSurface
    var showsDiagnostics = false
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.callout.weight(.semibold))
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(QuillCodePalette.muted)
                if let actionLabel = issue.actionLabel {
                    if let onAction {
                        Button(actionLabel, action: onAction)
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    } else {
                        Text(actionLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                }
                if showsDiagnostics && !issue.diagnostics.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Diagnostics")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(QuillCodePalette.muted)
                        ForEach(issue.diagnostics) { diagnostic in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(diagnostic.label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(QuillCodePalette.muted)
                                    .frame(width: 96, alignment: .leading)
                                Text(diagnostic.value)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tint: Color {
        issue.severity == .error ? QuillCodePalette.red : QuillCodePalette.yellow
    }
}

struct QuillCodeSettingsDraft: Equatable {
    var apiBaseURL: String = ""
    var authMode: TrustedRouterAuthMode = .oauth
    var developerOverrideEnabled: Bool = false
    var replacementAPIKey: String = ""
    var shouldClearAPIKey: Bool = false

    init() {}

    init(settings: WorkspaceSettingsSurface) {
        self.apiBaseURL = settings.apiBaseURL
        self.authMode = settings.authMode
        self.developerOverrideEnabled = settings.developerOverrideEnabled
    }

    var canSave: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var update: WorkspaceSettingsUpdate {
        WorkspaceSettingsUpdate(
            apiBaseURL: apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            authMode: authMode,
            developerOverrideEnabled: developerOverrideEnabled,
            replacementAPIKey: replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines),
            shouldClearAPIKey: shouldClearAPIKey
        )
    }
}
