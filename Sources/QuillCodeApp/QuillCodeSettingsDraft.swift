import Foundation
import QuillCodeCore

struct QuillCodeSettingsDraft: Equatable {
    var apiBaseURL: String = ""
    var authMode: TrustedRouterAuthMode = .oauth
    var developerOverrideEnabled: Bool = false
    var replacementAPIKey: String = ""
    var shouldClearAPIKey: Bool = false
    var computerUseApprovedBundleIdentifiersText: String = ""
    var computerUseApprovedAppNamesText: String = ""
    var browserAllowedDomainsText: String = ""
    var browserBlockedDomainsText: String = ""

    init() {}

    init(settings: WorkspaceSettingsSurface) {
        self.apiBaseURL = settings.apiBaseURL
        self.authMode = settings.authMode
        self.developerOverrideEnabled = settings.developerOverrideEnabled
        self.computerUseApprovedBundleIdentifiersText = Self.joinedApprovals(
            settings.computerUseApprovedBundleIdentifiers
        )
        self.computerUseApprovedAppNamesText = Self.joinedApprovals(settings.computerUseApprovedAppNames)
        self.browserAllowedDomainsText = Self.joinedApprovals(settings.browserAllowedDomains)
        self.browserBlockedDomainsText = Self.joinedApprovals(settings.browserBlockedDomains)
    }

    var canSave: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var update: WorkspaceSettingsUpdate {
        let trimmedReplacementAPIKey = replacementAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceSettingsUpdate(
            apiBaseURL: apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            authMode: authMode,
            developerOverrideEnabled: developerOverrideEnabled,
            replacementAPIKey: trimmedReplacementAPIKey.isEmpty ? nil : trimmedReplacementAPIKey,
            shouldClearAPIKey: shouldClearAPIKey,
            computerUseApprovedBundleIdentifiers: Self.approvals(from: computerUseApprovedBundleIdentifiersText),
            computerUseApprovedAppNames: Self.approvals(from: computerUseApprovedAppNamesText),
            browserAllowedDomains: Self.approvals(from: browserAllowedDomainsText),
            browserBlockedDomains: Self.approvals(from: browserBlockedDomainsText)
        )
    }

    mutating func clearComputerUseApprovals() {
        computerUseApprovedBundleIdentifiersText = ""
        computerUseApprovedAppNamesText = ""
    }

    mutating func clearBrowserDomainPolicy() {
        browserAllowedDomainsText = ""
        browserBlockedDomainsText = ""
    }

    private static func joinedApprovals(_ approvals: [String]) -> String {
        approvals.joined(separator: "\n")
    }

    private static func approvals(from text: String) -> [String] {
        text
            .replacingOccurrences(of: ",", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
