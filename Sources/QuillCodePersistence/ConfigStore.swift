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
        config.notificationPreferences = notificationPreferences
        config.runSpendPeriodLimits = runSpendPeriodLimits
        config.managedWorktrees = managedWorktrees
        return config
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var lines = [
            "default_model = \(Self.quote(config.defaultModel))",
            "mode = \(Self.quote(config.mode.rawValue))",
            "api_base_url = \(Self.quote(config.apiBaseURL))",
            "auth_mode = \(Self.quote(config.authMode.rawValue))",
            "developer_override_enabled = \(Self.boolString(config.developerOverrideEnabled))"
        ]
        Self.appendNotificationPreferences(config.notificationPreferences, to: &lines)
        Self.appendOptionalDouble(config.runSpendFuseUSD, key: "run_spend_fuse_usd", to: &lines)
        Self.appendOptionalDouble(
            config.runSpendPeriodLimits.dailyUSD,
            key: "run_spend_daily_limit_usd",
            to: &lines
        )
        Self.appendOptionalDouble(
            config.runSpendPeriodLimits.weeklyUSD,
            key: "run_spend_weekly_limit_usd",
            to: &lines
        )
        Self.appendOptionalDouble(
            config.runSpendPeriodLimits.monthlyUSD,
            key: "run_spend_monthly_limit_usd",
            to: &lines
        )
        if let rootPath = config.managedWorktrees.rootPath {
            lines.append("managed_worktree_root = \(Self.quote(rootPath))")
        }
        Self.appendBoolean(
            config.managedWorktrees.automaticCleanupEnabled,
            key: "managed_worktree_automatic_cleanup_enabled",
            to: &lines
        )
        lines.append("managed_worktree_retention_limit = \(config.managedWorktrees.retentionLimit)")
        Self.appendRepeatedValues(config.favoriteModels, key: "favorite_model", to: &lines)
        Self.appendRepeatedValues(
            config.computerUseApprovedBundleIdentifiers,
            key: "computer_use_approved_bundle_identifier",
            to: &lines
        )
        Self.appendRepeatedValues(
            config.computerUseApprovedAppNames,
            key: "computer_use_approved_app_name",
            to: &lines
        )
        Self.appendRepeatedValues(config.browserAllowedDomains, key: "browser_allowed_domain", to: &lines)
        Self.appendRepeatedValues(config.browserBlockedDomains, key: "browser_blocked_domain", to: &lines)
        if let account = config.trustedRouterAccount {
            if let userID = account.userID {
                lines.append("trustedrouter_user_id = \(Self.quote(userID))")
            }
            if let subject = account.subject {
                lines.append("trustedrouter_subject = \(Self.quote(subject))")
            }
            if let email = account.email {
                lines.append("trustedrouter_email = \(Self.quote(email))")
            }
            if let walletAddress = account.walletAddress {
                lines.append("trustedrouter_wallet_address = \(Self.quote(walletAddress))")
            }
        }
        let body = lines.joined(separator: "\n")
        try body.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func appendRepeatedValues(_ values: [String], key: String, to lines: inout [String]) {
        for value in values {
            lines.append("\(key) = \(quote(value))")
        }
    }

    private static func appendNotificationPreferences(
        _ preferences: QuillCodeNotificationPreferences,
        to lines: inout [String]
    ) {
        appendBoolean(
            preferences.agentRunNotificationsEnabled,
            key: "agent_run_notifications_enabled",
            to: &lines
        )
        appendBoolean(
            preferences.agentRunNotificationsOnlyWhenInactive,
            key: "agent_run_notifications_only_when_inactive",
            to: &lines
        )
        appendBoolean(
            preferences.automationNotificationsEnabled,
            key: "automation_notifications_enabled",
            to: &lines
        )
    }

    private static func appendBoolean(_ value: Bool, key: String, to lines: inout [String]) {
        lines.append("\(key) = \(boolString(value))")
    }

    private static func appendOptionalDouble(_ value: Double?, key: String, to lines: inout [String]) {
        guard let value else { return }
        lines.append("\(key) = \(String(format: "%.6f", value))")
    }

    private static func boolString(_ value: Bool) -> String {
        value ? "true" : "false"
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

    private static func quote(_ value: String) -> String {
        // Escape backslash FIRST, then the chars that would break the flat key=value line format.
        // Newlines especially: an unescaped '\n' splits the value across physical lines, and load()
        // then rejects the '=' -less fragment — corrupting the ENTIRE config, not just this value.
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
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
