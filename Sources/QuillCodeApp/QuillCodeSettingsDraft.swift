import Foundation
import QuillCodeCore

struct QuillCodeSettingsDraft: Equatable {
    var apiBaseURL: String = ""
    var authMode: TrustedRouterAuthMode = .oauth
    var developerOverrideEnabled: Bool = false
    var replacementAPIKey: String = ""
    var shouldClearAPIKey: Bool = false

    init() {}

    init(settings: WorkspaceSettingsSurface) {
        apiBaseURL = settings.apiBaseURL
        authMode = settings.authMode
        developerOverrideEnabled = settings.developerOverrideEnabled
    }

    var canSave: Bool {
        !trimmedAPIBaseURL.isEmpty
    }

    var update: WorkspaceSettingsUpdate {
        WorkspaceSettingsUpdate(
            apiBaseURL: trimmedAPIBaseURL,
            authMode: authMode,
            developerOverrideEnabled: developerOverrideEnabled,
            replacementAPIKey: trimmedReplacementAPIKey.isEmpty ? nil : trimmedReplacementAPIKey,
            shouldClearAPIKey: shouldClearAPIKey
        )
    }

    private var trimmedAPIBaseURL: String {
        apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedReplacementAPIKey: String {
        replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
