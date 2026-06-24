import Foundation
import QuillCodeCore
import QuillCodeSafety
import TrustedRouter

public struct TrustedRouterSafetyModelClient: SafetyModelClient {
    public var sessionStore: (any TrustedRouterSessionStore)?
    public var apiKeyOverride: String?
    public var baseURL: String

    public init(
        sessionStore: (any TrustedRouterSessionStore)? = nil,
        apiKeyOverride: String? = nil,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL
    ) {
        self.sessionStore = sessionStore
        self.apiKeyOverride = apiKeyOverride
        self.baseURL = baseURL
    }

    public func review(prompt: String, model: String) async throws -> String {
        let apiKey = try configuredAPIKey()
        let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL))
        let completion = try await client.chatCompletions(
            model: model,
            messages: [
                ["role": "system", "content": "Return only the requested JSON object."],
                ["role": "user", "content": prompt]
            ],
            params: TrustedRouterChatParameters.jsonObjectResponse
        )
        guard let text = completion.choices.first?.message.content,
              !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        else {
            throw TrustedRouterAgentError.emptyResponse
        }
        return text
    }

    private func configuredAPIKey() throws -> String {
        try TrustedRouterAPIKeyResolver(
            sessionStore: sessionStore,
            apiKeyOverride: apiKeyOverride
        ).configuredAPIKey()
    }
}
