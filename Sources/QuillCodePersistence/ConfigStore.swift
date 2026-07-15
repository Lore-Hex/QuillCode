import Foundation
import QuillCodeCore

public enum ConfigStoreError: Error, CustomStringConvertible {
    case invalidLine(String)

    public var description: String {
        switch self {
        case .invalidLine(let line):
            return "Invalid config line: \(line)"
        }
    }
}

public struct ConfigStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfig()
        }
        if let document = try? ConfigDocumentStore(fileURL: fileURL).load() {
            return Self.config(from: document)
        }

        // Keep accepting early QuillCode files containing invalid bare values. New writes always
        // use the strict TOML document store, but silently discarding an older user's settings
        // because one boolean was malformed would be a worse migration failure.
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var config = AppConfig()
        var explicitAuthMode: TrustedRouterAuthMode?
        var legacyDeveloperOverrideEnabled: Bool?
        var account = TrustedRouterAccountProfile()
        var favoriteModels: [String] = []
        var computerUseApprovedBundleIdentifiers: [String] = []
        var computerUseApprovedAppNames: [String] = []
        var browserAllowedDomains: [String] = []
        var browserBlockedDomains: [String] = []
        var disabledSkillPaths: [String] = []
        var disabledSkillNames: [String] = []
        var notificationPreferences = QuillCodeNotificationPreferences()
        var runSpendPeriodLimits = RunSpendPeriodLimits()
        var managedWorktrees = ManagedWorktreeSettings()
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { throw ConfigStoreError.invalidLine(rawLine) }
            let key = parts[0]
            let value = Self.unquote(parts[1])
            switch key {
            case "default_model":
                config.defaultModel = TrustedRouterDefaults.normalizedDefaultModelID(value)
            case "review_model":
                config.reviewModel = AppConfig.normalizedReviewModelID(value)
            case "review_delivery":
                config.reviewDelivery = CodeReviewDelivery(rawValue: value) ?? config.reviewDelivery
            case "mode":
                config.mode = AgentMode(rawValue: value) ?? config.mode
            case "api_base_url":
                config.apiBaseURL = value
            case "auth_mode":
                explicitAuthMode = TrustedRouterAuthMode(rawValue: value) ?? config.authMode
            case "developer_override_enabled":
                legacyDeveloperOverrideEnabled = (value == "true")
            case "trustedrouter_user_id":
                account.userID = value
            case "trustedrouter_subject":
                account.subject = value
            case "trustedrouter_email":
                account.email = value
            case "trustedrouter_wallet_address":
                account.walletAddress = value
            case "favorite_model":
                favoriteModels.append(value)
            case "computer_use_approved_bundle_identifier":
                computerUseApprovedBundleIdentifiers.append(value)
            case "computer_use_approved_app_name":
                computerUseApprovedAppNames.append(value)
            case "browser_allowed_domain":
                browserAllowedDomains.append(value)
            case "browser_blocked_domain":
                browserBlockedDomains.append(value)
            case "disabled_skill_path":
                disabledSkillPaths.append(value)
            case "disabled_skill_name":
                disabledSkillNames.append(value)
            case "agent_run_notifications_enabled":
                notificationPreferences.agentRunNotificationsEnabled = Self.boolValue(value)
                    ?? notificationPreferences.agentRunNotificationsEnabled
            case "agent_run_notifications_only_when_inactive":
                notificationPreferences.agentRunNotificationsOnlyWhenInactive = Self.boolValue(value)
                    ?? notificationPreferences.agentRunNotificationsOnlyWhenInactive
            case "automation_notifications_enabled":
                notificationPreferences.automationNotificationsEnabled = Self.boolValue(value)
                    ?? notificationPreferences.automationNotificationsEnabled
            case "run_spend_fuse_usd":
                config.runSpendFuseUSD = RunSpendLedger.normalizedFuse(Self.doubleValue(value))
            case "run_spend_daily_limit_usd":
                runSpendPeriodLimits.dailyUSD = RunSpendPeriodLimits.normalizedLimit(Self.doubleValue(value))
            case "run_spend_weekly_limit_usd":
                runSpendPeriodLimits.weeklyUSD = RunSpendPeriodLimits.normalizedLimit(Self.doubleValue(value))
            case "run_spend_monthly_limit_usd":
                runSpendPeriodLimits.monthlyUSD = RunSpendPeriodLimits.normalizedLimit(Self.doubleValue(value))
            case "managed_worktree_root":
                managedWorktrees.rootPath = ManagedWorktreeSettings.normalizedRootPath(value)
            case "managed_worktree_automatic_cleanup_enabled":
                managedWorktrees.automaticCleanupEnabled = Self.boolValue(value)
                    ?? managedWorktrees.automaticCleanupEnabled
            case "managed_worktree_retention_limit":
                if let limit = Self.intValue(value) {
                    managedWorktrees.retentionLimit = ManagedWorktreeSettings.normalizedRetentionLimit(limit)
                }
            case "max_tool_steps":
                if let steps = Self.intValue(value) {
                    config.maxToolSteps = max(1, steps)
                }
            default:
                continue
            }
        }
        if let explicitAuthMode {
            config.authMode = explicitAuthMode
            config.developerOverrideEnabled = explicitAuthMode == .developerOverride
        } else if legacyDeveloperOverrideEnabled == true {
            config.authMode = .developerOverride
            config.developerOverrideEnabled = true
        }
        let normalizedAccount = TrustedRouterAccountProfile(
            userID: account.userID,
            subject: account.subject,
            email: account.email,
            walletAddress: account.walletAddress
        )
        config.trustedRouterAccount = normalizedAccount.isEmpty ? nil : normalizedAccount
        config.favoriteModels = AppConfig(favoriteModels: favoriteModels).favoriteModels
        config.computerUseApprovedBundleIdentifiers = AppConfig(
            computerUseApprovedBundleIdentifiers: computerUseApprovedBundleIdentifiers
        ).computerUseApprovedBundleIdentifiers
        config.computerUseApprovedAppNames = AppConfig(
            computerUseApprovedAppNames: computerUseApprovedAppNames
        ).computerUseApprovedAppNames
        let browserPolicy = BrowserDomainPolicy(
            allowedDomains: browserAllowedDomains,
            blockedDomains: browserBlockedDomains
        )
        config.browserAllowedDomains = browserPolicy.allowedDomains
        config.browserBlockedDomains = browserPolicy.blockedDomains
        config.skillConfiguration = SkillConfiguration(
            disabledPaths: disabledSkillPaths,
            disabledNames: disabledSkillNames
        )
        config.notificationPreferences = notificationPreferences
        config.runSpendPeriodLimits = runSpendPeriodLimits
        config.managedWorktrees = managedWorktrees
        return config
    }

    public func save(_ config: AppConfig) throws {
        let store = ConfigDocumentStore(fileURL: fileURL)
        var document = (try? store.load()) ?? ConfigDocument()

        for key in Self.ownedKeys { document.values.removeValue(forKey: key) }
        document.values["model"] = .string(config.defaultModel)
        document.values["review_model"] = config.reviewModel.map(ConfigValue.string)
        document.values["review_delivery"] = .string(config.reviewDelivery.rawValue)
        document.values["mode"] = .string(config.mode.rawValue)
        document.values["api_base_url"] = .string(config.apiBaseURL)
        document.values["auth_mode"] = .string(config.authMode.rawValue)
        document.values["developer_override_enabled"] = .bool(config.developerOverrideEnabled)
        document.values["model_provider"] = .string("trustedrouter")
        let access = Self.accessValues(for: config.mode)
        document.values["sandbox_mode"] = .string(access.sandbox)
        document.values["approvals_reviewer"] = .string(access.reviewer)
        document.values["approval_policy"] = .string("on-request")

        let notifications = config.notificationPreferences
        document.values["agent_run_notifications_enabled"] = .bool(notifications.agentRunNotificationsEnabled)
        document.values["agent_run_notifications_only_when_inactive"] = .bool(
            notifications.agentRunNotificationsOnlyWhenInactive
        )
        document.values["automation_notifications_enabled"] = .bool(
            notifications.automationNotificationsEnabled
        )
        document.values["run_spend_fuse_usd"] = config.runSpendFuseUSD.map(ConfigValue.number)
        document.values["run_spend_daily_limit_usd"] = config.runSpendPeriodLimits.dailyUSD.map(
            ConfigValue.number
        )
        document.values["run_spend_weekly_limit_usd"] = config.runSpendPeriodLimits.weeklyUSD.map(
            ConfigValue.number
        )
        document.values["run_spend_monthly_limit_usd"] = config.runSpendPeriodLimits.monthlyUSD.map(
            ConfigValue.number
        )
        document.values["managed_worktree_root"] = config.managedWorktrees.rootPath.map(ConfigValue.string)
        document.values["managed_worktree_automatic_cleanup_enabled"] = .bool(
            config.managedWorktrees.automaticCleanupEnabled
        )
        document.values["managed_worktree_retention_limit"] = .integer(
            Int64(config.managedWorktrees.retentionLimit)
        )
        document.values["max_tool_steps"] = .integer(Int64(config.maxToolSteps))
        document.values["favorite_model"] = .stringArray(config.favoriteModels)
        document.values["computer_use_approved_bundle_identifier"] = .stringArray(
            config.computerUseApprovedBundleIdentifiers
        )
        document.values["computer_use_approved_app_name"] = .stringArray(
            config.computerUseApprovedAppNames
        )
        document.values["browser_allowed_domain"] = .stringArray(config.browserAllowedDomains)
        document.values["browser_blocked_domain"] = .stringArray(config.browserBlockedDomains)
        document.values["disabled_skill_path"] = .stringArray(config.skillConfiguration.disabledPaths)
        document.values["disabled_skill_name"] = .stringArray(config.skillConfiguration.disabledNames)
        document.values["keyboard_shortcuts"] = Self.configValue(from: config.keyboardShortcuts)

        if let account = config.trustedRouterAccount {
            document.values["trustedrouter_user_id"] = account.userID.map(ConfigValue.string)
            document.values["trustedrouter_subject"] = account.subject.map(ConfigValue.string)
            document.values["trustedrouter_email"] = account.email.map(ConfigValue.string)
            document.values["trustedrouter_wallet_address"] = account.walletAddress.map(ConfigValue.string)
        }
        try store.save(document)
    }

    private static let ownedKeys: Set<String> = [
        "default_model", "model", "review_model", "review_delivery", "mode", "api_base_url",
        "auth_mode", "developer_override_enabled", "model_provider", "sandbox_mode",
        "approvals_reviewer", "approval_policy", "trustedrouter_user_id", "trustedrouter_subject",
        "trustedrouter_email", "trustedrouter_wallet_address", "favorite_model",
        "computer_use_approved_bundle_identifier", "computer_use_approved_app_name",
        "browser_allowed_domain", "browser_blocked_domain", "disabled_skill_path",
        "disabled_skill_name", "agent_run_notifications_enabled",
        "agent_run_notifications_only_when_inactive", "automation_notifications_enabled",
        "run_spend_fuse_usd", "run_spend_daily_limit_usd", "run_spend_weekly_limit_usd",
        "run_spend_monthly_limit_usd", "managed_worktree_root",
        "managed_worktree_automatic_cleanup_enabled", "managed_worktree_retention_limit",
        "keyboard_shortcuts", "max_tool_steps"
    ]

    private static func config(from document: ConfigDocument) -> AppConfig {
        let values = document.values
        let explicitAuthMode = values.string("auth_mode").flatMap(TrustedRouterAuthMode.init(rawValue:))
        let legacyDeveloperOverride = values.bool("developer_override_enabled") == true
        let authMode = explicitAuthMode ?? (legacyDeveloperOverride ? .developerOverride : .oauth)
        let account = TrustedRouterAccountProfile(
            userID: values.string("trustedrouter_user_id"),
            subject: values.string("trustedrouter_subject"),
            email: values.string("trustedrouter_email"),
            walletAddress: values.string("trustedrouter_wallet_address")
        )
        let mode = values.string("mode").flatMap(AgentMode.init(rawValue:))
            ?? modeFromCodexAccess(values)
        let notifications = QuillCodeNotificationPreferences(
            agentRunNotificationsEnabled: values.bool("agent_run_notifications_enabled") ?? true,
            agentRunNotificationsOnlyWhenInactive: values.bool(
                "agent_run_notifications_only_when_inactive"
            ) ?? true,
            automationNotificationsEnabled: values.bool("automation_notifications_enabled") ?? true
        )
        let limits = RunSpendPeriodLimits(
            dailyUSD: values.double("run_spend_daily_limit_usd"),
            weeklyUSD: values.double("run_spend_weekly_limit_usd"),
            monthlyUSD: values.double("run_spend_monthly_limit_usd")
        )
        let managedWorktrees = ManagedWorktreeSettings(
            rootPath: values.string("managed_worktree_root"),
            automaticCleanupEnabled: values.bool("managed_worktree_automatic_cleanup_enabled") ?? true,
            retentionLimit: values.int("managed_worktree_retention_limit")
                ?? ManagedWorktreeSettings.defaultRetentionLimit
        )
        let keyboardShortcuts = values["keyboard_shortcuts"].flatMap {
            decode(KeyboardShortcutPreferences.self, from: $0)
        } ?? KeyboardShortcutPreferences()

        return AppConfig(
            defaultModel: values.string("model")
                ?? values.string("default_model")
                ?? TrustedRouterDefaults.defaultModel,
            mode: mode,
            apiBaseURL: values.string("api_base_url") ?? TrustedRouterDefaults.defaultAPIBaseURL,
            authMode: authMode,
            developerOverrideEnabled: authMode == .developerOverride,
            trustedRouterAccount: account.isEmpty ? nil : account,
            favoriteModels: values.stringArray("favorite_model"),
            computerUseApprovedBundleIdentifiers: values.stringArray(
                "computer_use_approved_bundle_identifier"
            ),
            computerUseApprovedAppNames: values.stringArray("computer_use_approved_app_name"),
            browserAllowedDomains: values.stringArray("browser_allowed_domain"),
            browserBlockedDomains: values.stringArray("browser_blocked_domain"),
            notificationPreferences: notifications,
            runSpendFuseUSD: values["run_spend_fuse_usd"] == nil
                ? 1.0
                : RunSpendLedger.normalizedFuse(values.double("run_spend_fuse_usd")),
            runSpendPeriodLimits: limits,
            managedWorktrees: managedWorktrees,
            keyboardShortcuts: keyboardShortcuts,
            skillConfiguration: SkillConfiguration(
                disabledPaths: values.stringArray("disabled_skill_path"),
                disabledNames: values.stringArray("disabled_skill_name")
            ),
            maxToolSteps: max(1, values.int("max_tool_steps") ?? AppConfig.defaultMaxToolSteps),
            reviewModel: values.string("review_model"),
            reviewDelivery: values.string("review_delivery").flatMap(CodeReviewDelivery.init(rawValue:))
                ?? .current
        )
    }

    private static func modeFromCodexAccess(_ values: [String: ConfigValue]) -> AgentMode {
        guard values["sandbox_mode"] != nil || values["approvals_reviewer"] != nil else {
            return .auto
        }
        if values.string("sandbox_mode") == "read-only" { return .readOnly }
        return values.string("approvals_reviewer") == "auto_review" ? .auto : .review
    }

    private static func accessValues(for mode: AgentMode) -> (sandbox: String, reviewer: String) {
        switch mode {
        case .auto: ("workspace-write", "auto_review")
        case .review: ("workspace-write", "user")
        case .readOnly, .plan: ("read-only", "user")
        }
    }

    private static func configValue<T: Encodable>(from value: T) -> ConfigValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(ConfigValue.self, from: data)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from value: ConfigValue) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func boolValue(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func doubleValue(_ value: String) -> Double? {
        Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func intValue(_ value: String) -> Int? {
        Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func unquote(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return trimmed
        }
        let inner = String(trimmed.dropFirst().dropLast())
        var output = ""
        var isEscaping = false
        for character in inner {
            if isEscaping {
                // Decode the escape sequences quote() emits: \n -> newline, \r -> CR, and
                // \\ / \" -> the literal char (default). Without the n/r cases a round-tripped
                // newline would silently decode back to the literal letter 'n'.
                switch character {
                case "n": output.append("\n")
                case "r": output.append("\r")
                default: output.append(character)
                }
                isEscaping = false
            } else if character == "\\" {
                isEscaping = true
            } else {
                output.append(character)
            }
        }
        if isEscaping {
            output.append("\\")
        }
        return output
    }
}
