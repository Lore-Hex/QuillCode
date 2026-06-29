import Foundation
import QuillCodeCore
import TrustedRouter

public enum TrustedRouterAgentError: Error, CustomStringConvertible {
    case missingAPIKey
    case emptyResponse
    case invalidActionJSON(String)
    case emptyToolArguments(String)
    case streamingHTTPError(statusCode: Int, body: String)

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
        case .streamingHTTPError(let statusCode, let body):
            return TrustedRouterErrorBodyFormatter.streamingMessage(
                statusCode: statusCode,
                body: body
            )
        }
    }
}

public struct TrustedRouterLLMClient: UsageStreamingLLMClient {
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
        let events = try await actionEventStream(
            thread: thread,
            userMessage: userMessage,
            tools: tools
        )
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in events {
                        if case .text(let chunk) = event {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func actionEventStream(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AsyncThrowingStream<AgentTextStreamEvent, Error> {
        let apiKey = try configuredAPIKey()
        let client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL))
        let messages = promptBuilder.messages(thread: thread, userMessage: userMessage, tools: tools)
        let (bytes, response) = try await client.rawStreamRequest(
            method: "POST",
            path: "/chat/completions",
            headers: ["accept": "text/event-stream"],
            body: try Self.chatCompletionBody(model: model, messages: messages)
        )
        if response.statusCode >= 400 {
            throw TrustedRouterAgentError.streamingHTTPError(
                statusCode: response.statusCode,
                body: try await Self.drain(bytes)
            )
        }

        let chunks = iterSseEvents(bytes: bytes, type: UsageChatCompletionChunk.self)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in chunks {
                        if let reasoning = chunk.choices.first?.delta?.reasoning, !reasoning.isEmpty {
                            continuation.yield(.reasoning(reasoning))
                        }
                        if let content = chunk.choices.first?.delta?.content, !content.isEmpty {
                            continuation.yield(.text(content))
                        }
                        if let usage = chunk.usage {
                            continuation.yield(.usage(usage))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public static func collectAction(from stream: AsyncThrowingStream<String, Error>) async throws -> AgentAction {
        try await AgentActionStreamCollector.collect(
            from: stream,
            emptyError: TrustedRouterAgentError.emptyResponse
        )
    }

    public func configuredAPIKey() throws -> String {
        try TrustedRouterAPIKeyResolver(
            sessionStore: sessionStore,
            apiKeyOverride: apiKeyOverride
        ).configuredAPIKey()
    }

    private static func chatCompletionBody(model: String, messages: [[String: Any]]) throws -> Data {
        var body = TrustedRouterChatParameters.jsonObjectResponse
        body["model"] = model
        body["messages"] = messages
        body["stream"] = true
        body["stream_options"] = ["include_usage": true]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private static func drain(_ bytes: TrustedRouterByteStream) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct UsageChatCompletionChunk: Decodable {
    var choices: [Choice]
    var usage: ModelTokenUsage?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.choices = try container.decodeIfPresent([Choice].self, forKey: .choices) ?? []
        self.usage = try container.decodeIfPresent(ModelTokenUsage.self, forKey: .usage)
    }

    private enum CodingKeys: String, CodingKey {
        case choices
        case usage
    }

    struct Choice: Decodable {
        var delta: Delta?

        struct Delta: Decodable {
            var content: String?
            var reasoning: String?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.content = try container.decodeIfPresent(String.self, forKey: .content)
                self.reasoning = try Self.firstNonEmptyString(in: container, keys: [
                    .reasoningContent,
                    .reasoning,
                    .reasoningSummary
                ])
            }

            private enum CodingKeys: String, CodingKey {
                case content
                case reasoning
                case reasoningContent = "reasoning_content"
                case reasoningSummary = "reasoning_summary"
            }

            private static func firstNonEmptyString(
                in container: KeyedDecodingContainer<CodingKeys>,
                keys: [CodingKeys]
            ) throws -> String? {
                for key in keys {
                    guard let value = try container.decodeIfPresent(String.self, forKey: key),
                          value.contains(where: { !$0.isWhitespace })
                    else {
                        continue
                    }
                    return value
                }
                return nil
            }
        }
    }
}
