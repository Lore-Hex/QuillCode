import Foundation
import QuillCodeCore
import QuillComputerUseKit

public struct ComputerUseSettingsRuntime: Sendable, Hashable {
    public var status: ComputerUseStatus
    public var foregroundApplication: ComputerUseApplication?

    public init(
        status: ComputerUseStatus = .permissionStatus(
            screenRecordingGranted: false,
            accessibilityGranted: false
        ),
        foregroundApplication: ComputerUseApplication? = nil
    ) {
        self.status = status
        self.foregroundApplication = foregroundApplication
    }

    public init(topBarState: TopBarState) {
        self.status = topBarState.computerUseStatus
        self.foregroundApplication = topBarState.computerUseForegroundApplication
    }
}

public struct WorkspaceSettingsSurface: Codable, Sendable, Hashable {
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var hasStoredAPIKey: Bool
    public var signInURL: String
    public var apiKeyStatusLabel: String
    public var loginStatusLabel: String
    public var accountLabel: String?
    public var runtimeIssue: RuntimeIssueSurface?
    public var modelCatalogStatusLabel: String
    public var modelCatalogStatusDetail: String?
    public var modelProviderHealthLabel: String?
    public var modelProviderHealthDetail: String?
    public var computerUseStatus: ComputerUseStatus
    public var computerUseSetupCommand: WorkspaceCommandSurface
    public var computerUseScreenRecordingCommand: WorkspaceCommandSurface
    public var computerUseAccessibilityCommand: WorkspaceCommandSurface
    public var computerUseRefreshCommand: WorkspaceCommandSurface
    public var computerUseStatusLabel: String
    public var computerUseSetupSummary: String
    public var computerUseNextAction: String
    public var computerUseOnboardingSteps: [String]
    public var computerUseRequirements: [ComputerUseRequirementSurface]
    public var computerUseForegroundApplication: ComputerUseApplication?
    public var computerUseApprovedBundleIdentifiers: [String]
    public var computerUseApprovedAppNames: [String]
    public var computerUseApprovalStatusLabel: String
    public var computerUseApprovalSummary: String
    public var browserAllowedDomains: [String]
    public var browserBlockedDomains: [String]
    public var browserDomainPolicyStatusLabel: String
    public var browserDomainPolicySummary: String
    public var notificationPreferences: QuillCodeNotificationPreferences
    public var notificationStatusLabel: String
    public var notificationSummary: String
    public var runSpendFuseUSD: Double?
    public var runSpendPeriodLimits: RunSpendPeriodLimits
    public var runSpendLimitStatusLabel: String
    public var runSpendLimitSummary: String
    public var managedWorktreeRootPath: String
    public var managedWorktreeDefaultRootPath: String
    public var managedWorktreeAutomaticCleanupEnabled: Bool
    public var managedWorktreeRetentionLimit: Int
    public var managedWorktreeStatusLabel: String
    public var managedWorktreeSummary: String

    public init(
        config: AppConfig,
        hasStoredAPIKey: Bool,
        runtimeIssue: RuntimeIssueSurface? = nil,
        computerUseRuntime: ComputerUseSettingsRuntime = ComputerUseSettingsRuntime(),
        modelCatalogStatus: ModelCatalogStatus = .bundled,
        modelProviderHealthSummary: ModelProviderHealthSummary = .summarize([]),
        managedWorktreeDefaultRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quillcode/worktrees")
    ) {
        self.apiBaseURL = config.apiBaseURL
        self.authMode = config.authMode
        self.developerOverrideEnabled = config.developerOverrideEnabled
        self.hasStoredAPIKey = hasStoredAPIKey
        self.signInURL = TrustedRouterDefaults.loopbackCallbackURL
        self.accountLabel = config.trustedRouterAccount?.displayLabel
        self.runtimeIssue = runtimeIssue
        self.modelCatalogStatusLabel = modelCatalogStatus.statusLabel()
        self.modelCatalogStatusDetail = modelCatalogStatus.detailLabel()
        self.modelProviderHealthLabel = modelProviderHealthSummary.label
        self.modelProviderHealthDetail = modelProviderHealthSummary.detail
        self.computerUseStatus = computerUseRuntime.status
        self.computerUseSetupCommand = WorkspaceCommandSurface.computerUseSetup(
            isEnabled: !computerUseRuntime.status.available
        )
        self.computerUseScreenRecordingCommand = WorkspaceCommandSurface.computerUseScreenRecordingSettings(
            isEnabled: !computerUseRuntime.status.screenRecordingGranted
        )
        self.computerUseAccessibilityCommand = WorkspaceCommandSurface.computerUseAccessibilitySettings(
            isEnabled: !computerUseRuntime.status.accessibilityGranted
        )
        self.computerUseRefreshCommand = WorkspaceCommandSurface.computerUseRefresh
        self.computerUseStatusLabel = ComputerUseSettingsProjection.statusLabel(computerUseRuntime.status)
        self.computerUseSetupSummary = ComputerUseSettingsProjection.setupSummary(computerUseRuntime.status)
        self.computerUseNextAction = ComputerUseSettingsProjection.nextAction(computerUseRuntime.status)
        self.computerUseOnboardingSteps = ComputerUseSettingsProjection.onboardingSteps(
            status: computerUseRuntime.status,
            config: config
        )
        self.computerUseRequirements = ComputerUseSettingsProjection.requirements(
            status: computerUseRuntime.status,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
        self.computerUseForegroundApplication = computerUseRuntime.foregroundApplication
        self.computerUseApprovedBundleIdentifiers = config.computerUseApprovedBundleIdentifiers
        self.computerUseApprovedAppNames = config.computerUseApprovedAppNames
        self.computerUseApprovalStatusLabel = ComputerUseSettingsProjection.approvalStatusLabel(config)
        self.computerUseApprovalSummary = ComputerUseSettingsProjection.approvalSummary(config)
        let browserPolicy = config.browserDomainPolicy
        self.browserAllowedDomains = browserPolicy.allowedDomains
        self.browserBlockedDomains = browserPolicy.blockedDomains
        self.browserDomainPolicyStatusLabel = browserPolicy.statusLabel
        self.browserDomainPolicySummary = browserPolicy.summary
        self.notificationPreferences = config.notificationPreferences
        self.notificationStatusLabel = NotificationSettingsProjection.statusLabel(config.notificationPreferences)
        self.notificationSummary = NotificationSettingsProjection.summary(config.notificationPreferences)
        self.runSpendFuseUSD = config.runSpendFuseUSD
        self.runSpendPeriodLimits = config.runSpendPeriodLimits
        self.runSpendLimitStatusLabel = RunSpendLimitSettingsProjection.statusLabel(config)
        self.runSpendLimitSummary = RunSpendLimitSettingsProjection.summary(config)
        let resolvedWorktreeRoot = config.managedWorktrees.resolvedRoot(
            defaultRoot: managedWorktreeDefaultRoot,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        self.managedWorktreeRootPath = resolvedWorktreeRoot.path
        self.managedWorktreeDefaultRootPath = managedWorktreeDefaultRoot.standardizedFileURL.path
        self.managedWorktreeAutomaticCleanupEnabled = config.managedWorktrees.automaticCleanupEnabled
        self.managedWorktreeRetentionLimit = config.managedWorktrees.retentionLimit
        self.managedWorktreeStatusLabel = ManagedWorktreeSettingsProjection.statusLabel(config.managedWorktrees)
        self.managedWorktreeSummary = ManagedWorktreeSettingsProjection.summary(
            config.managedWorktrees,
            resolvedRoot: resolvedWorktreeRoot
        )
        switch config.authMode {
        case .oauth:
            self.apiKeyStatusLabel = hasStoredAPIKey ? "Signed in" : "Not signed in"
            if hasStoredAPIKey, let accountLabel {
                self.loginStatusLabel = "Signed in as \(accountLabel)"
            } else {
                self.loginStatusLabel = hasStoredAPIKey ? "TrustedRouter OAuth ready" : "TrustedRouter login required"
            }
        case .developerOverride:
            self.apiKeyStatusLabel = hasStoredAPIKey ? "API key configured" : "No API key saved"
            self.loginStatusLabel = hasStoredAPIKey
                ? "TrustedRouter developer override ready"
                : "Developer override needs an API key"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case apiBaseURL
        case authMode
        case developerOverrideEnabled
        case hasStoredAPIKey
        case signInURL
        case apiKeyStatusLabel
        case loginStatusLabel
        case accountLabel
        case runtimeIssue
        case modelCatalogStatusLabel
        case modelCatalogStatusDetail
        case modelProviderHealthLabel
        case modelProviderHealthDetail
        case computerUseStatus
        case computerUseSetupCommand
        case computerUseScreenRecordingCommand
        case computerUseAccessibilityCommand
        case computerUseRefreshCommand
        case computerUseStatusLabel
        case computerUseSetupSummary
        case computerUseNextAction
        case computerUseOnboardingSteps
        case computerUseRequirements
        case computerUseForegroundApplication
        case computerUseApprovedBundleIdentifiers
        case computerUseApprovedAppNames
        case computerUseApprovalStatusLabel
        case computerUseApprovalSummary
        case browserAllowedDomains
        case browserBlockedDomains
        case browserDomainPolicyStatusLabel
        case browserDomainPolicySummary
        case notificationPreferences
        case notificationStatusLabel
        case notificationSummary
        case runSpendFuseUSD
        case runSpendPeriodLimits
        case runSpendLimitStatusLabel
        case runSpendLimitSummary
        case managedWorktreeRootPath
        case managedWorktreeDefaultRootPath
        case managedWorktreeAutomaticCleanupEnabled
        case managedWorktreeRetentionLimit
        case managedWorktreeStatusLabel
        case managedWorktreeSummary
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        self.authMode = try container.decode(TrustedRouterAuthMode.self, forKey: .authMode)
        self.developerOverrideEnabled = try container.decode(Bool.self, forKey: .developerOverrideEnabled)
        self.hasStoredAPIKey = try container.decode(Bool.self, forKey: .hasStoredAPIKey)
        self.signInURL = try container.decode(String.self, forKey: .signInURL)
        self.apiKeyStatusLabel = try container.decode(String.self, forKey: .apiKeyStatusLabel)
        self.loginStatusLabel = try container.decode(String.self, forKey: .loginStatusLabel)
        self.accountLabel = try container.decodeIfPresent(String.self, forKey: .accountLabel)
        self.runtimeIssue = try container.decodeIfPresent(RuntimeIssueSurface.self, forKey: .runtimeIssue)
        self.modelCatalogStatusLabel = try container.decodeIfPresent(String.self, forKey: .modelCatalogStatusLabel)
            ?? ModelCatalogStatus.bundled.statusLabel()
        self.modelCatalogStatusDetail = try container.decodeIfPresent(String.self, forKey: .modelCatalogStatusDetail)
            ?? ModelCatalogStatus.bundled.detailLabel()
        self.modelProviderHealthLabel = try container.decodeIfPresent(String.self, forKey: .modelProviderHealthLabel)
        self.modelProviderHealthDetail = try container.decodeIfPresent(String.self, forKey: .modelProviderHealthDetail)
        let decodedComputerUseStatus = try container.decodeIfPresent(
            ComputerUseStatus.self,
            forKey: .computerUseStatus
        ) ?? ComputerUseSettingsProjection.defaultStatus()
        self.computerUseStatus = decodedComputerUseStatus
        self.computerUseSetupCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseSetupCommand
        ) ?? .computerUseSetup(isEnabled: !decodedComputerUseStatus.available)
        self.computerUseScreenRecordingCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseScreenRecordingCommand
        ) ?? .computerUseScreenRecordingSettings(isEnabled: !decodedComputerUseStatus.screenRecordingGranted)
        self.computerUseAccessibilityCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseAccessibilityCommand
        ) ?? .computerUseAccessibilitySettings(isEnabled: !decodedComputerUseStatus.accessibilityGranted)
        self.computerUseRefreshCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .computerUseRefreshCommand
        ) ?? .computerUseRefresh
        self.computerUseStatusLabel = try container.decodeIfPresent(String.self, forKey: .computerUseStatusLabel)
            ?? ComputerUseSettingsProjection.statusLabel(decodedComputerUseStatus)
        self.computerUseSetupSummary = try container.decodeIfPresent(String.self, forKey: .computerUseSetupSummary)
            ?? ComputerUseSettingsProjection.setupSummary(decodedComputerUseStatus)
        self.computerUseNextAction = try container.decodeIfPresent(String.self, forKey: .computerUseNextAction)
            ?? ComputerUseSettingsProjection.nextAction(decodedComputerUseStatus)
        let approvalConfig = AppConfig(
            computerUseApprovedBundleIdentifiers: try container.decodeIfPresent(
                [String].self,
                forKey: .computerUseApprovedBundleIdentifiers
            ) ?? [],
            computerUseApprovedAppNames: try container.decodeIfPresent(
                [String].self,
                forKey: .computerUseApprovedAppNames
            ) ?? []
        )
        self.computerUseOnboardingSteps = try container.decodeIfPresent(
            [String].self,
            forKey: .computerUseOnboardingSteps
        ) ?? ComputerUseSettingsProjection.onboardingSteps(
            status: decodedComputerUseStatus,
            config: approvalConfig
        )
        self.computerUseRequirements = try container.decodeIfPresent(
            [ComputerUseRequirementSurface].self,
            forKey: .computerUseRequirements
        ) ?? ComputerUseSettingsProjection.requirements(
            status: decodedComputerUseStatus,
            screenRecordingCommand: computerUseScreenRecordingCommand,
            accessibilityCommand: computerUseAccessibilityCommand
        )
        self.computerUseForegroundApplication = try container.decodeIfPresent(
            ComputerUseApplication.self,
            forKey: .computerUseForegroundApplication
        )
        self.computerUseApprovedBundleIdentifiers = approvalConfig.computerUseApprovedBundleIdentifiers
        self.computerUseApprovedAppNames = approvalConfig.computerUseApprovedAppNames
        self.computerUseApprovalStatusLabel = try container.decodeIfPresent(
            String.self,
            forKey: .computerUseApprovalStatusLabel
        ) ?? ComputerUseSettingsProjection.approvalStatusLabel(approvalConfig)
        self.computerUseApprovalSummary = try container.decodeIfPresent(
            String.self,
            forKey: .computerUseApprovalSummary
        ) ?? ComputerUseSettingsProjection.approvalSummary(approvalConfig)
        let browserPolicy = BrowserDomainPolicy(
            allowedDomains: try container.decodeIfPresent([String].self, forKey: .browserAllowedDomains) ?? [],
            blockedDomains: try container.decodeIfPresent([String].self, forKey: .browserBlockedDomains) ?? []
        )
        self.browserAllowedDomains = browserPolicy.allowedDomains
        self.browserBlockedDomains = browserPolicy.blockedDomains
        self.browserDomainPolicyStatusLabel = try container.decodeIfPresent(
            String.self,
            forKey: .browserDomainPolicyStatusLabel
        ) ?? browserPolicy.statusLabel
        self.browserDomainPolicySummary = try container.decodeIfPresent(
            String.self,
            forKey: .browserDomainPolicySummary
        ) ?? browserPolicy.summary
        let decodedNotificationPreferences = try container.decodeIfPresent(
            QuillCodeNotificationPreferences.self,
            forKey: .notificationPreferences
        ) ?? QuillCodeNotificationPreferences()
        self.notificationPreferences = decodedNotificationPreferences
        self.notificationStatusLabel = try container.decodeIfPresent(
            String.self,
            forKey: .notificationStatusLabel
        ) ?? NotificationSettingsProjection.statusLabel(decodedNotificationPreferences)
        self.notificationSummary = try container.decodeIfPresent(
            String.self,
            forKey: .notificationSummary
        ) ?? NotificationSettingsProjection.summary(decodedNotificationPreferences)
        self.runSpendFuseUSD = RunSpendLedger.normalizedFuse(
            try container.decodeIfPresent(Double.self, forKey: .runSpendFuseUSD) ?? 1.0
        )
        self.runSpendPeriodLimits = try container.decodeIfPresent(
            RunSpendPeriodLimits.self,
            forKey: .runSpendPeriodLimits
        ) ?? RunSpendPeriodLimits()
        let spendConfig = AppConfig(
            runSpendFuseUSD: runSpendFuseUSD,
            runSpendPeriodLimits: runSpendPeriodLimits
        )
        self.runSpendLimitStatusLabel = try container.decodeIfPresent(
            String.self,
            forKey: .runSpendLimitStatusLabel
        ) ?? RunSpendLimitSettingsProjection.statusLabel(spendConfig)
        self.runSpendLimitSummary = try container.decodeIfPresent(
            String.self,
            forKey: .runSpendLimitSummary
        ) ?? RunSpendLimitSettingsProjection.summary(spendConfig)
        let fallbackRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".quillcode/worktrees")
            .standardizedFileURL.path
        self.managedWorktreeRootPath = try container.decodeIfPresent(
            String.self,
            forKey: .managedWorktreeRootPath
        ) ?? fallbackRoot
        self.managedWorktreeDefaultRootPath = try container.decodeIfPresent(
            String.self,
            forKey: .managedWorktreeDefaultRootPath
        ) ?? fallbackRoot
        self.managedWorktreeAutomaticCleanupEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .managedWorktreeAutomaticCleanupEnabled
        ) ?? true
        self.managedWorktreeRetentionLimit = ManagedWorktreeSettings.normalizedRetentionLimit(
            try container.decodeIfPresent(Int.self, forKey: .managedWorktreeRetentionLimit)
                ?? ManagedWorktreeSettings.defaultRetentionLimit
        )
        let worktreeSettings = ManagedWorktreeSettings(
            rootPath: managedWorktreeRootPath,
            automaticCleanupEnabled: managedWorktreeAutomaticCleanupEnabled,
            retentionLimit: managedWorktreeRetentionLimit
        )
        self.managedWorktreeStatusLabel = try container.decodeIfPresent(
            String.self,
            forKey: .managedWorktreeStatusLabel
        ) ?? ManagedWorktreeSettingsProjection.statusLabel(worktreeSettings)
        self.managedWorktreeSummary = try container.decodeIfPresent(
            String.self,
            forKey: .managedWorktreeSummary
        ) ?? ManagedWorktreeSettingsProjection.summary(
            worktreeSettings,
            resolvedRoot: URL(fileURLWithPath: managedWorktreeRootPath)
        )
    }
}

enum ManagedWorktreeSettingsProjection {
    static func statusLabel(_ settings: ManagedWorktreeSettings) -> String {
        settings.automaticCleanupEnabled ? "Keep \(settings.retentionLimit)" : "Manual cleanup"
    }

    static func summary(_ settings: ManagedWorktreeSettings, resolvedRoot: URL) -> String {
        if settings.automaticCleanupEnabled {
            return "New task worktrees use \(resolvedRoot.path). QuillCode snapshots and removes the oldest eligible worktrees after the newest \(settings.retentionLimit)."
        }
        return "New task worktrees use \(resolvedRoot.path). Automatic deletion is off; archive cleanup still saves work before removing disposable worktrees."
    }
}

enum NotificationSettingsProjection {
    static func statusLabel(_ preferences: QuillCodeNotificationPreferences) -> String {
        switch (
            preferences.agentRunNotificationsEnabled,
            preferences.automationNotificationsEnabled,
            preferences.agentRunNotificationsOnlyWhenInactive
        ) {
        case (true, true, true):
            return "Smart"
        case (true, true, false):
            return "All activity"
        case (true, false, _):
            return "Agent runs"
        case (false, true, _):
            return "Automations"
        case (false, false, _):
            return "Off"
        }
    }

    static func summary(_ preferences: QuillCodeNotificationPreferences) -> String {
        if !preferences.anyNotificationEnabled {
            return "Desktop notifications are disabled for agent runs and automations."
        }

        var parts: [String] = []
        if preferences.agentRunNotificationsEnabled {
            parts.append(preferences.agentRunNotificationsOnlyWhenInactive
                ? "Agent runs notify only when QuillCode is in the background"
                : "Agent runs notify whenever they need attention")
        }
        if preferences.automationNotificationsEnabled {
            parts.append("Automation runs post completion alerts")
        }
        return parts.joined(separator: ". ") + "."
    }
}

enum RunSpendLimitSettingsProjection {
    static func statusLabel(_ config: AppConfig) -> String {
        switch (config.runSpendFuseUSD, config.runSpendPeriodLimits.hasAnyLimit) {
        case (.some, true):
            return "Fuse + caps"
        case (.some, false):
            return "Fuse"
        case (.none, true):
            return "Caps"
        case (.none, false):
            return "Uncapped"
        }
    }

    static func summary(_ config: AppConfig) -> String {
        var parts: [String] = []
        if let fuse = config.runSpendFuseUSD {
            parts.append("review each thread after \(RunSpendLedger.costLabel(fuse))")
        }
        if config.runSpendPeriodLimits.hasAnyLimit {
            parts.append("show local day, week, and month cap rows in the top bar")
        }
        if parts.isEmpty {
            return "Local spend tracking is visible after priced model usage; no local caps are configured."
        }
        return """
        Local spend controls \(parts.joined(separator: " and ")). \
        These do not replace TrustedRouter account limits.
        """
    }
}
