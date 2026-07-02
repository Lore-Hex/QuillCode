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
            "developer_override_enabled = \(config.developerOverrideEnabled ? "true" : "false")"
        ]
        for model in config.favoriteModels {
            lines.append("favorite_model = \(Self.quote(model))")
        }
        for bundleIdentifier in config.computerUseApprovedBundleIdentifiers {
            lines.append("computer_use_approved_bundle_identifier = \(Self.quote(bundleIdentifier))")
        }
        for appName in config.computerUseApprovedAppNames {
            lines.append("computer_use_approved_app_name = \(Self.quote(appName))")
        }
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

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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
                output.append(character)
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
