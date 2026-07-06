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
    public var browserAllowedDomains: [String]
    public var browserBlockedDomains: [String]
    public var notificationPreferences: QuillCodeNotificationPreferences
    public var runSpendFuseUSD: Double?
    public var runSpendPeriodLimits: RunSpendPeriodLimits

    public init(
        apiBaseURL: String,
        authMode: TrustedRouterAuthMode = .oauth,
        developerOverrideEnabled: Bool = false,
        replacementAPIKey: String? = nil,
        shouldClearAPIKey: Bool = false,
        computerUseApprovedBundleIdentifiers: [String] = [],
        computerUseApprovedAppNames: [String] = [],
        browserAllowedDomains: [String] = [],
        browserBlockedDomains: [String] = [],
        notificationPreferences: QuillCodeNotificationPreferences = QuillCodeNotificationPreferences(),
        runSpendFuseUSD: Double? = 1.0,
        runSpendPeriodLimits: RunSpendPeriodLimits = RunSpendPeriodLimits()
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
        let browserPolicy = BrowserDomainPolicy(
            allowedDomains: browserAllowedDomains,
            blockedDomains: browserBlockedDomains
        )
        self.browserAllowedDomains = browserPolicy.allowedDomains
        self.browserBlockedDomains = browserPolicy.blockedDomains
        self.notificationPreferences = notificationPreferences
        self.runSpendFuseUSD = RunSpendLedger.normalizedFuse(runSpendFuseUSD)
        self.runSpendPeriodLimits = runSpendPeriodLimits
    }
}
