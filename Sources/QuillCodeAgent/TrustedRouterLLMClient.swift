import Foundation
import QuillCodeCore
import QuillCodeSafety
import TrustedRouter

public enum TrustedRouterAgentError: Error, CustomStringConvertible {
    case missingAPIKey
    case emptyResponse
    case invalidActionJSON(String)
    case emptyToolArguments(String)

    public var description: String {
        switch self {
        case .missingAPIKey:
            return "TrustedRouter API key is not configured. Sign in or enable the developer override."
        case .emptyResponse:
            return "TrustedRouter returned an empty response."
        case .invalidActionJSON(let text):
            return "Model did not return a valid QuillCode action JSON object: \(text)"
        case .emptyToolArguments(let toolName):
            return "Model returned an empty argument object for \(toolName)."
        }
    }
}

public struct TrustedRouterLLMClient: StreamingLLMClient {
    public static var jsonObjectResponseParameters: [String: Any] {
        ["response_format": ["type": "json_object"]]
    }

    public var promptBuilder: TrustedRouterPromptBuilder
    public var sessionStore: (any TrustedRouterSessionStore)?
    public var apiKeyOverride: String?
    public var model: String
    public var baseURL: String

    public init(
        promptBuilder: TrustedRouterPromptBuilder = .init(),
        sessionStore: (any TrustedRouterSessionStore)? = nil,
        apiKeyOverride: String? = nil,
        model: String = TrustedRouterDefaults.defaultModel,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL
    ) {
        self.promptBuilder = promptBuilder
        self.sessionStore = sessionStore
        self.apiKeyOverride = apiKeyOverride
        self.model = model
        self.baseURL = baseURL
    }

    public func nextAction(thread: ChatThread, userMessage: String, tools: [ToolDefinition]) async throws -> AgentAction {
        let stream = try await actionTextStream(thread: thread, userMessage: userMessage, tools: tools)
        return try await Self.collectAction(from: stream)
    }

    public func actionTextStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = try configuredAPIKey()
        let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL))
        let messages = promptBuilder.messages(thread: thread, userMessage: userMessage, tools: tools)
        return try await client.chatCompletionsText(
            model: model,
            messages: messages,
            params: Self.jsonObjectResponseParameters
        )
    }

    public static func collectAction(from stream: AsyncThrowingStream<String, Error>) async throws -> AgentAction {
        try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: TrustedRouterAgentError.emptyResponse
        )
    }

    public func configuredAPIKey() throws -> String {
        if let apiKeyOverride, !apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKeyOverride
        }
        if let key = try sessionStore?.apiKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        throw TrustedRouterAgentError.missingAPIKey
    }
}

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
            params: TrustedRouterLLMClient.jsonObjectResponseParameters
        )
        guard let text = completion.choices.first?.message.content,
              !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        else {
            throw TrustedRouterAgentError.emptyResponse
        }
        return text
    }

    private func configuredAPIKey() throws -> String {
        if let apiKeyOverride, !apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKeyOverride
        }
        if let key = try sessionStore?.apiKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        throw TrustedRouterAgentError.missingAPIKey
    }
}
