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

public struct AppConfig: Codable, Sendable, Hashable {
    public var defaultModel: String
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

    private enum CodingKeys: String, CodingKey {
        case defaultModel
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
        runSpendFuseUSD: Double? = 1.0
    ) {
        self.defaultModel = TrustedRouterDefaults.normalizedDefaultModelID(defaultModel)
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
    }

    public init(
        defaultModel: String,
        mode: AgentMode,
        apiBaseURL: String,
        authMode: TrustedRouterAuthMode,
        developerOverrideEnabled: Bool,
        trustedRouterAccount: TrustedRouterAccountProfile?,
        favoriteModels: [String],
        computerUseApprovedBundleIdentifiers: [String],
        computerUseApprovedAppNames: [String]
    ) {
        self.init(
            defaultModel: defaultModel,
            mode: mode,
            apiBaseURL: apiBaseURL,
            authMode: authMode,
            developerOverrideEnabled: developerOverrideEnabled,
            trustedRouterAccount: trustedRouterAccount,
            favoriteModels: favoriteModels,
            computerUseApprovedBundleIdentifiers: computerUseApprovedBundleIdentifiers,
            computerUseApprovedAppNames: computerUseApprovedAppNames,
            browserAllowedDomains: [],
            browserBlockedDomains: [],
            notificationPreferences: QuillCodeNotificationPreferences(),
            runSpendFuseUSD: 1.0
        )
    }

    public var browserDomainPolicy: BrowserDomainPolicy {
        BrowserDomainPolicy(
            allowedDomains: browserAllowedDomains,
            blockedDomains: browserBlockedDomains
        )
    }

    public init(
        defaultModel: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        apiBaseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        developerOverrideEnabled: Bool
    ) {
        self.init(
            defaultModel: defaultModel,
            mode: mode,
            apiBaseURL: apiBaseURL,
            authMode: developerOverrideEnabled ? .developerOverride : .oauth,
            developerOverrideEnabled: developerOverrideEnabled,
            trustedRouterAccount: nil,
            favoriteModels: [],
            computerUseApprovedBundleIdentifiers: [],
            computerUseApprovedAppNames: [],
            browserAllowedDomains: [],
            browserBlockedDomains: [],
            notificationPreferences: QuillCodeNotificationPreferences(),
            runSpendFuseUSD: 1.0
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
            runSpendFuseUSD: try container.decodeIfPresent(Double.self, forKey: .runSpendFuseUSD) ?? 1.0
        )
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
