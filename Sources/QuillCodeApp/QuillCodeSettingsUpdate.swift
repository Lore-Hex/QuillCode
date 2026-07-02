import Foundation
import QuillCodeCore

public struct WorkspaceSettingsUpdate: Sendable, Hashable {
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var replacementAPIKey: String?
    public var shouldClearAPIKey: Bool
    public var computerUseApprovedBundleIdentifiers: [String]
    public var computerUseApprovedAppNames: [String]

    public init(
        apiBaseURL: String,
        authMode: TrustedRouterAuthMode = .oauth,
        developerOverrideEnabled: Bool = false,
        replacementAPIKey: String? = nil,
        shouldClearAPIKey: Bool = false,
        computerUseApprovedBundleIdentifiers: [String] = [],
        computerUseApprovedAppNames: [String] = []
    ) {
        self.apiBaseURL = apiBaseURL
        self.authMode = developerOverrideEnabled ? .developerOverride : authMode
        self.developerOverrideEnabled = developerOverrideEnabled || authMode == .developerOverride
        self.replacementAPIKey = replacementAPIKey
        self.shouldClearAPIKey = shouldClearAPIKey

        let approvalConfig = AppConfig(
            computerUseApprovedBundleIdentifiers: computerUseApprovedBundleIdentifiers,
            computerUseApprovedAppNames: computerUseApprovedAppNames
        )
        self.computerUseApprovedBundleIdentifiers = approvalConfig.computerUseApprovedBundleIdentifiers
        self.computerUseApprovedAppNames = approvalConfig.computerUseApprovedAppNames
    }
}
