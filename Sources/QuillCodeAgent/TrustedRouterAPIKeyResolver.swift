import Foundation

public struct TrustedRouterAPIKeyResolver: Sendable {
    public var sessionStore: (any TrustedRouterSessionStore)?
    public var apiKeyOverride: String?

    public init(
        sessionStore: (any TrustedRouterSessionStore)? = nil,
        apiKeyOverride: String? = nil
    ) {
        self.sessionStore = sessionStore
        self.apiKeyOverride = apiKeyOverride
    }

    public func configuredAPIKey() throws -> String {
        if let key = Self.nonEmptyKey(apiKeyOverride) {
            return key
        }
        if let key = try Self.nonEmptyKey(sessionStore?.apiKey()) {
            return key
        }
        throw TrustedRouterAgentError.missingAPIKey
    }

    private static func nonEmptyKey(_ key: String?) -> String? {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
