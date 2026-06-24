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

    private enum CodingKeys: String, CodingKey {
        case defaultModel
        case mode
        case apiBaseURL
        case authMode
        case developerOverrideEnabled
        case trustedRouterAccount
        case favoriteModels
    }

    public init(
        defaultModel: String = TrustedRouterDefaults.defaultModel,
        mode: AgentMode = .auto,
        apiBaseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        authMode: TrustedRouterAuthMode = .oauth,
        developerOverrideEnabled: Bool = false,
        trustedRouterAccount: TrustedRouterAccountProfile? = nil,
        favoriteModels: [String] = []
    ) {
        self.defaultModel = TrustedRouterDefaults.normalizedDefaultModelID(defaultModel)
        self.mode = mode
        self.apiBaseURL = apiBaseURL
        self.authMode = developerOverrideEnabled ? .developerOverride : authMode
        self.developerOverrideEnabled = developerOverrideEnabled || authMode == .developerOverride
        self.trustedRouterAccount = trustedRouterAccount?.isEmpty == true ? nil : trustedRouterAccount
        self.favoriteModels = Self.normalizedModelIDs(favoriteModels)
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
            favoriteModels: []
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            defaultModel: try container.decodeIfPresent(String.self, forKey: .defaultModel) ?? TrustedRouterDefaults.defaultModel,
            mode: try container.decodeIfPresent(AgentMode.self, forKey: .mode) ?? .auto,
            apiBaseURL: try container.decodeIfPresent(String.self, forKey: .apiBaseURL) ?? TrustedRouterDefaults.defaultAPIBaseURL,
            authMode: try container.decodeIfPresent(TrustedRouterAuthMode.self, forKey: .authMode) ?? .oauth,
            developerOverrideEnabled: try container.decodeIfPresent(Bool.self, forKey: .developerOverrideEnabled) ?? false,
            trustedRouterAccount: try container.decodeIfPresent(TrustedRouterAccountProfile.self, forKey: .trustedRouterAccount),
            favoriteModels: try container.decodeIfPresent([String].self, forKey: .favoriteModels) ?? []
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
}
