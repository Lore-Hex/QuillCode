import Foundation
import QuillCodeCore
import QuillComputerUseKit

struct QuillCodeSettingsDraft: Equatable {
    var apiBaseURL: String = ""
    var authMode: TrustedRouterAuthMode = .oauth
    var developerOverrideEnabled: Bool = false
    var replacementAPIKey: String = ""
    var shouldClearAPIKey: Bool = false
    var reviewModelText: String = ""
    var reviewDelivery: CodeReviewDelivery = .current
    var defaultPersonality: QuillCodePersonality = .defaultValue
    var computerUseApprovedBundleIdentifiersText: String = ""
    var computerUseApprovedAppNamesText: String = ""
    var browserAllowedDomainsText: String = ""
    var browserBlockedDomainsText: String = ""
    var agentRunNotificationsEnabled: Bool = true
    var agentRunNotificationsOnlyWhenInactive: Bool = true
    var automationNotificationsEnabled: Bool = true
    var runSpendFuseUSDText: String = ""
    var runSpendDailyLimitUSDText: String = ""
    var runSpendWeeklyLimitUSDText: String = ""
    var runSpendMonthlyLimitUSDText: String = ""
    var managedWorktreeRootPathText: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".quillcode/worktrees").path
    var managedWorktreeDefaultRootPath: String = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".quillcode/worktrees").path
    var managedWorktreeAutomaticCleanupEnabled: Bool = true
    var managedWorktreeRetentionLimit: Int = ManagedWorktreeSettings.defaultRetentionLimit

    init() {}

    init(settings: WorkspaceSettingsSurface) {
        self.apiBaseURL = settings.apiBaseURL
        self.authMode = settings.authMode
        self.developerOverrideEnabled = settings.developerOverrideEnabled
        self.reviewModelText = settings.reviewModel ?? ""
        self.reviewDelivery = settings.reviewDelivery
        self.defaultPersonality = settings.defaultPersonality
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
        self.runSpendFuseUSDText = Self.optionalCurrencyText(settings.runSpendFuseUSD)
        self.runSpendDailyLimitUSDText = Self.optionalCurrencyText(settings.runSpendPeriodLimits.dailyUSD)
        self.runSpendWeeklyLimitUSDText = Self.optionalCurrencyText(settings.runSpendPeriodLimits.weeklyUSD)
        self.runSpendMonthlyLimitUSDText = Self.optionalCurrencyText(settings.runSpendPeriodLimits.monthlyUSD)
        self.managedWorktreeRootPathText = settings.managedWorktreeRootPath
        self.managedWorktreeDefaultRootPath = settings.managedWorktreeDefaultRootPath
        self.managedWorktreeAutomaticCleanupEnabled = settings.managedWorktreeAutomaticCleanupEnabled
        self.managedWorktreeRetentionLimit = settings.managedWorktreeRetentionLimit
    }

    var canSave: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Self.isValidWorktreeRoot(managedWorktreeRootPathText)
            && isReviewModelValid
    }

    var isReviewModelValid: Bool {
        let trimmed = reviewModelText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let canonicalID = TrustedRouterDefaults.canonicalModelID(trimmed)
        return !canonicalID.isEmpty
            && canonicalID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
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
            ),
            runSpendFuseUSD: Self.optionalCurrency(from: runSpendFuseUSDText),
            runSpendPeriodLimits: RunSpendPeriodLimits(
                dailyUSD: Self.optionalCurrency(from: runSpendDailyLimitUSDText),
                weeklyUSD: Self.optionalCurrency(from: runSpendWeeklyLimitUSDText),
                monthlyUSD: Self.optionalCurrency(from: runSpendMonthlyLimitUSDText)
            ),
            managedWorktrees: ManagedWorktreeSettings(
                rootPath: Self.explicitWorktreeRoot(
                    managedWorktreeRootPathText,
                    defaultRoot: managedWorktreeDefaultRootPath
                ),
                automaticCleanupEnabled: managedWorktreeAutomaticCleanupEnabled,
                retentionLimit: managedWorktreeRetentionLimit
            ),
            reviewModel: normalizedReviewModel,
            reviewDelivery: reviewDelivery,
            defaultPersonality: defaultPersonality
        )
    }

    private var normalizedReviewModel: String? {
        guard isReviewModelValid else { return nil }
        return AppConfig.normalizedReviewModelID(reviewModelText)
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

    private static func optionalCurrencyText(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(format: "%.2f", value)
    }

    private static func optionalCurrency(from text: String) -> Double? {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$", with: "")
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private static func isValidWorktreeRoot(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "~" || trimmed.hasPrefix("~/") || trimmed.hasPrefix("/")
    }

    private static func explicitWorktreeRoot(_ text: String, defaultRoot: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == defaultRoot ? nil : trimmed
    }
}
