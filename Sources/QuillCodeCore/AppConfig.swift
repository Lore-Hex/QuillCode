import Foundation

public enum TrustedRouterAuthMode: String, Codable, Sendable, CaseIterable, Hashable {
    case oauth
    case developerOverride = "developer-override"
}

public struct TrustedRouterAccountProfile: Codable, Sendable, Hashable {
    public var userID: String?
    public var subject: String?
    public var email: String?
    public var walletAddress: String?

    public init(
        userID: String? = nil,
        subject: String? = nil,
        email: String? = nil,
        walletAddress: String? = nil
    ) {
        self.userID = Self.trimmed(userID)
        self.subject = Self.trimmed(subject)
        self.email = Self.trimmed(email)
        self.walletAddress = Self.trimmed(walletAddress)
    }

    public var isEmpty: Bool {
        [userID, subject, email, walletAddress].allSatisfy { ($0 ?? "").isEmpty }
    }

    public var displayLabel: String {
        if let email, !email.isEmpty { return email }
        if let userID, !userID.isEmpty { return userID }
        if let subject, !subject.isEmpty { return subject }
        if let walletAddress, !walletAddress.isEmpty { return walletAddress }
        return "TrustedRouter account"
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct RunSpendPeriodLimits: Codable, Sendable, Hashable {
    public var dailyUSD: Double?
    public var weeklyUSD: Double?
    public var monthlyUSD: Double?

    public init(
        dailyUSD: Double? = nil,
        weeklyUSD: Double? = nil,
        monthlyUSD: Double? = nil
    ) {
        self.dailyUSD = Self.normalizedLimit(dailyUSD)
        self.weeklyUSD = Self.normalizedLimit(weeklyUSD)
        self.monthlyUSD = Self.normalizedLimit(monthlyUSD)
    }

    public var hasAnyLimit: Bool {
        dailyUSD != nil || weeklyUSD != nil || monthlyUSD != nil
    }

    public static func normalizedLimit(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }
}

public struct ManagedWorktreeSettings: Codable, Sendable, Hashable {
    public static let defaultRetentionLimit = 15
    public static let retentionLimitRange = 1...1_000

    /// nil uses QuillCode's application-owned worktree directory.
    public var rootPath: String?
    public var automaticCleanupEnabled: Bool
    public var retentionLimit: Int

    public init(
        rootPath: String? = nil,
        automaticCleanupEnabled: Bool = true,
        retentionLimit: Int = Self.defaultRetentionLimit
    ) {
        self.rootPath = Self.normalizedRootPath(rootPath)
        self.automaticCleanupEnabled = automaticCleanupEnabled
        self.retentionLimit = Self.normalizedRetentionLimit(retentionLimit)
    }

    public func resolvedRoot(defaultRoot: URL, homeDirectory: URL) -> URL {
        guard let rootPath else { return defaultRoot.standardizedFileURL }
        if rootPath == "~" {
            return homeDirectory.standardizedFileURL
        }
        if rootPath.hasPrefix("~/") {
            return homeDirectory
                .appendingPathComponent(String(rootPath.dropFirst(2)))
                .standardizedFileURL
        }
        return URL(fileURLWithPath: rootPath).standardizedFileURL
    }

    public static func normalizedRetentionLimit(_ value: Int) -> Int {
        min(max(value, retentionLimitRange.lowerBound), retentionLimitRange.upperBound)
    }

    public static func normalizedRootPath(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed == "~" || trimmed.hasPrefix("~/") || trimmed.hasPrefix("/") else {
            return nil
        }
        return trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case rootPath
        case automaticCleanupEnabled
        case retentionLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rootPath: try container.decodeIfPresent(String.self, forKey: .rootPath),
            automaticCleanupEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .automaticCleanupEnabled
            ) ?? true,
            retentionLimit: try container.decodeIfPresent(Int.self, forKey: .retentionLimit)
                ?? Self.defaultRetentionLimit
        )
    }
}

public enum CodeReviewDelivery: String, Codable, Sendable, CaseIterable, Hashable {
    case current
    case detached
}

public struct AppConfig: Codable, Sendable, Hashable {
    /// Production per-turn tool-step budget. Deliberately much higher than
    /// `AgentRunner.defaultMaxToolSteps` (a conservative library default): a real coding task
    /// (edit → build → test → fix → re-test) routinely needs dozens of tool executions, and the
    /// spend fuse — not a tiny step count — is the primary runaway guard.
    public static let defaultMaxToolSteps = 64

    public var defaultModel: String
    /// nil uses the model selected for the current task.
    public var reviewModel: String?
    public var reviewDelivery: CodeReviewDelivery
    public var mode: AgentMode
    public var apiBaseURL: String
    public var authMode: TrustedRouterAuthMode
    public var developerOverrideEnabled: Bool
    public var trustedRouterAccount: TrustedRouterAccountProfile?
    public var favoriteModels: [String]
    public var computerUseApprovedBundleIdentifiers: [String]
    public var computerUseApprovedAppNames: [String]
    public var browserAllowedDomains: [String]
    public var browserBlockedDomains: [String]
    public var notificationPreferences: QuillCodeNotificationPreferences
    public var runSpendFuseUSD: Double?
    public var runSpendPeriodLimits: RunSpendPeriodLimits
    public var managedWorktrees: ManagedWorktreeSettings
    public var keyboardShortcuts: KeyboardShortcutPreferences
    /// Per-turn ceiling on agent tool executions. Always ≥ 1 (normalized on init).
    public var maxToolSteps: Int

    private enum CodingKeys: String, CodingKey {
        case defaultModel
        case reviewModel
        case reviewDelivery
        case mode
        case apiBaseURL
        case authMode
        case developerOverrideEnabled
        case trustedRouterAccount
        case favoriteModels
        case computerUseApprovedBundleIdentifiers
        case computerUseApprovedAppNames
        case browserAllowedDomains
        case browserBlockedDomains
        case notificationPreferences
        case runSpendFuseUSD
        case runSpendPeriodLimits
        case managedWorktrees
        case keyboardShortcuts
        case maxToolSteps
    }

    public init(
        defaultModel: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        apiBaseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        authMode: TrustedRouterAuthMode = .oauth,
        developerOverrideEnabled: Bool = false,
        trustedRouterAccount: TrustedRouterAccountProfile? = nil,
        favoriteModels: [String] = [],
        computerUseApprovedBundleIdentifiers: [String] = [],
        computerUseApprovedAppNames: [String] = [],
        browserAllowedDomains: [String] = [],
        browserBlockedDomains: [String] = [],
        notificationPreferences: QuillCodeNotificationPreferences = QuillCodeNotificationPreferences(),
        runSpendFuseUSD: Double? = 1.0,
        runSpendPeriodLimits: RunSpendPeriodLimits = RunSpendPeriodLimits(),
        managedWorktrees: ManagedWorktreeSettings = ManagedWorktreeSettings(),
        keyboardShortcuts: KeyboardShortcutPreferences = KeyboardShortcutPreferences(),
        maxToolSteps: Int = AppConfig.defaultMaxToolSteps,
        reviewModel: String? = nil,
        reviewDelivery: CodeReviewDelivery = .current
    ) {
        self.defaultModel = TrustedRouterDefaults.normalizedDefaultModelID(defaultModel)
        self.reviewModel = Self.normalizedReviewModelID(reviewModel)
        self.reviewDelivery = reviewDelivery
        self.mode = mode
        self.apiBaseURL = apiBaseURL
        self.authMode = developerOverrideEnabled ? .developerOverride : authMode
        self.developerOverrideEnabled = developerOverrideEnabled || authMode == .developerOverride
        self.trustedRouterAccount = trustedRouterAccount?.isEmpty == true ? nil : trustedRouterAccount
        self.favoriteModels = Self.normalizedModelIDs(favoriteModels)
        self.computerUseApprovedBundleIdentifiers = Self.normalizedComputerUseApprovals(
            computerUseApprovedBundleIdentifiers
        )
        self.computerUseApprovedAppNames = Self.normalizedComputerUseApprovals(computerUseApprovedAppNames)
        let browserPolicy = BrowserDomainPolicy(
            allowedDomains: browserAllowedDomains,
            blockedDomains: browserBlockedDomains
        )
        self.browserAllowedDomains = browserPolicy.allowedDomains
        self.browserBlockedDomains = browserPolicy.blockedDomains
        self.notificationPreferences = notificationPreferences
        self.runSpendFuseUSD = Self.normalizedRunSpendFuse(runSpendFuseUSD)
        self.runSpendPeriodLimits = runSpendPeriodLimits
        self.managedWorktrees = managedWorktrees
        self.keyboardShortcuts = keyboardShortcuts
        self.maxToolSteps = max(1, maxToolSteps)
    }

    public var browserDomainPolicy: BrowserDomainPolicy {
        BrowserDomainPolicy(
            allowedDomains: browserAllowedDomains,
            blockedDomains: browserBlockedDomains
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultModel = try container.decodeIfPresent(String.self, forKey: .defaultModel)
            ?? TrustedRouterDefaults.defaultModel
        let apiBaseURL = try container.decodeIfPresent(String.self, forKey: .apiBaseURL)
            ?? TrustedRouterDefaults.defaultAPIBaseURL
        let developerOverrideEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .developerOverrideEnabled
        ) ?? false
        let trustedRouterAccount = try container.decodeIfPresent(
            TrustedRouterAccountProfile.self,
            forKey: .trustedRouterAccount
        )
        self.init(
            defaultModel: defaultModel,
            mode: try container.decodeIfPresent(AgentMode.self, forKey: .mode) ?? .auto,
            apiBaseURL: apiBaseURL,
            authMode: try container.decodeIfPresent(TrustedRouterAuthMode.self, forKey: .authMode) ?? .oauth,
            developerOverrideEnabled: developerOverrideEnabled,
            trustedRouterAccount: trustedRouterAccount,
            favoriteModels: try container.decodeIfPresent([String].self, forKey: .favoriteModels) ?? [],
            computerUseApprovedBundleIdentifiers: try container.decodeIfPresent(
                [String].self,
                forKey: .computerUseApprovedBundleIdentifiers
            ) ?? [],
            computerUseApprovedAppNames: try container.decodeIfPresent(
                [String].self,
                forKey: .computerUseApprovedAppNames
            ) ?? [],
            browserAllowedDomains: try container.decodeIfPresent(
                [String].self,
                forKey: .browserAllowedDomains
            ) ?? [],
            browserBlockedDomains: try container.decodeIfPresent(
                [String].self,
                forKey: .browserBlockedDomains
            ) ?? [],
            notificationPreferences: try container.decodeIfPresent(
                QuillCodeNotificationPreferences.self,
                forKey: .notificationPreferences
            ) ?? QuillCodeNotificationPreferences(),
            runSpendFuseUSD: try container.decodeIfPresent(Double.self, forKey: .runSpendFuseUSD) ?? 1.0,
            runSpendPeriodLimits: try container.decodeIfPresent(
                RunSpendPeriodLimits.self,
                forKey: .runSpendPeriodLimits
            ) ?? RunSpendPeriodLimits(),
            managedWorktrees: try container.decodeIfPresent(
                ManagedWorktreeSettings.self,
                forKey: .managedWorktrees
            ) ?? ManagedWorktreeSettings(),
            keyboardShortcuts: try container.decodeIfPresent(
                KeyboardShortcutPreferences.self,
                forKey: .keyboardShortcuts
            ) ?? KeyboardShortcutPreferences(),
            maxToolSteps: try container.decodeIfPresent(Int.self, forKey: .maxToolSteps)
                ?? Self.defaultMaxToolSteps,
            reviewModel: try container.decodeIfPresent(String.self, forKey: .reviewModel),
            reviewDelivery: (try? container.decode(
                CodeReviewDelivery.self,
                forKey: .reviewDelivery
            )) ?? .current
        )
    }

    public static func normalizedReviewModelID(_ modelID: String?) -> String? {
        guard let modelID else { return nil }
        let canonicalID = TrustedRouterDefaults.canonicalModelID(modelID)
        guard !canonicalID.isEmpty else { return nil }
        return TrustedRouterDefaults.normalizedDefaultModelID(canonicalID)
    }

    private static func normalizedModelIDs(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = TrustedRouterDefaults.canonicalModelID(trimmed)
            guard !modelID.isEmpty, seen.insert(modelID).inserted else { continue }
            normalized.append(modelID)
        }
        return normalized
    }

    private static func normalizedRunSpendFuse(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func normalizedComputerUseApprovals(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            normalized.append(trimmed)
        }
        return normalized
    }
}
