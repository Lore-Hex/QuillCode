import Foundation
import QuillCodeCore
import QuillComputerUseKit

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
    var agentRunNotificationsEnabled: Bool = true
    var agentRunNotificationsOnlyWhenInactive: Bool = true
    var automationNotificationsEnabled: Bool = true

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
        self.agentRunNotificationsEnabled = settings.notificationPreferences.agentRunNotificationsEnabled
        self.agentRunNotificationsOnlyWhenInactive = settings
            .notificationPreferences
            .agentRunNotificationsOnlyWhenInactive
        self.automationNotificationsEnabled = settings.notificationPreferences.automationNotificationsEnabled
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
            browserBlockedDomains: Self.approvals(from: browserBlockedDomainsText),
            notificationPreferences: QuillCodeNotificationPreferences(
                agentRunNotificationsEnabled: agentRunNotificationsEnabled,
                agentRunNotificationsOnlyWhenInactive: agentRunNotificationsOnlyWhenInactive,
                automationNotificationsEnabled: automationNotificationsEnabled
            )
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

    mutating func addComputerUseApproval(for application: ComputerUseApplication) {
        if let bundleIdentifier = application.bundleIdentifier {
            computerUseApprovedBundleIdentifiersText = Self.textAddingApproval(
                bundleIdentifier,
                to: computerUseApprovedBundleIdentifiersText
            )
        } else if let name = application.name {
            computerUseApprovedAppNamesText = Self.textAddingApproval(
                name,
                to: computerUseApprovedAppNamesText
            )
        }
    }

    func hasComputerUseApproval(for application: ComputerUseApplication) -> Bool {
        if let bundleIdentifier = application.bundleIdentifier {
            return Self.approvals(from: computerUseApprovedBundleIdentifiersText)
                .contains { $0.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }
        }
        if let name = application.name {
            return Self.approvals(from: computerUseApprovedAppNamesText)
                .contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        return false
    }

    private static func joinedApprovals(_ approvals: [String]) -> String {
        approvals.joined(separator: "\n")
    }

    private static func textAddingApproval(_ approval: String, to text: String) -> String {
        let existing = approvals(from: text)
        guard !existing.contains(where: { $0.caseInsensitiveCompare(approval) == .orderedSame }) else {
            return joinedApprovals(existing)
        }
        return joinedApprovals(existing + [approval])
    }

    private static func approvals(from text: String) -> [String] {
        text
            .replacingOccurrences(of: ",", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
