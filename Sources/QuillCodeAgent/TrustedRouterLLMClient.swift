import Foundation
import QuillCodeCore
import TrustedRouter
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TrustedRouterAgentError: Error, CustomStringConvertible {
    case missingAPIKey
    case emptyResponse
    case invalidActionJSON(String)
    case emptyToolArguments(String)
    /// `rateLimit` carries the server's parsed rate-limit guidance (Retry-After / quota headers)
    /// when the response advertised any, so the retry backoff can honor the mandated wait.
    case streamingHTTPError(statusCode: Int, body: String, rateLimit: HTTPRateLimitDetails?)

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
        case .streamingHTTPError(let statusCode, let body, _):
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
    /// Prompt-cache breakpoints are placed automatically for Anthropic-family models (a large
    /// recurring cost and latency win for the agent loop) and never for other routes, whose
    /// requests stay byte-identical. Set `.disabled` to opt out entirely.
    public var promptCachingPolicy: TrustedRouterPromptCachingPolicy

    public init(
        promptBuilder: TrustedRouterPromptBuilder = .init(),
        sessionStore: (any TrustedRouterSessionStore)? = nil,
        apiKeyOverride: String? = nil,
        model: String = TrustedRouterDefaults.defaultModel,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL,
        promptCachingPolicy: TrustedRouterPromptCachingPolicy = .automatic
    ) {
        self.promptBuilder = promptBuilder
        self.sessionStore = sessionStore
        self.apiKeyOverride = apiKeyOverride
        self.model = model
        self.baseURL = baseURL
        self.promptCachingPolicy = promptCachingPolicy
    }

    /// A copy of this client that never adds prompt-cache breakpoints. Use it for one-shot
    /// auxiliary calls (context summaries, compaction) whose unique prompts are never re-sent,
    /// where a breakpoint could only ever be a cache write with no read.
    public func disablingPromptCaching() -> TrustedRouterLLMClient {
        var copy = self
        copy.promptCachingPolicy = .disabled
        return copy
    }

    public func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
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
        let assembled = promptBuilder.assembled(thread: thread, userMessage: userMessage, tools: tools)
        let (bytes, response) = try await client.rawStreamRequest(
            method: "POST",
            path: "/chat/completions",
            headers: ["accept": "text/event-stream"],
            body: try Self.chatCompletionBody(
                model: model,
                messages: assembled.messages,
                promptCachingPolicy: promptCachingPolicy,
                historyPrefixStable: assembled.historyPrefixStable
            )
        )
        if response.statusCode >= 400 {
            throw TrustedRouterAgentError.streamingHTTPError(
                statusCode: response.statusCode,
                body: try await Self.drain(bytes),
                rateLimit: HTTPRateLimitDetails.parse(headers: Self.headerMap(response))
            )
        }

        return TrustedRouterStreamingEventDecoder.eventStream(from: bytes)
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

    /// Internal (not private) so tests can assert over the exact serialized request JSON —
    /// cache breakpoints present or absent per policy, provider family, and prefix stability.
    ///
    /// `historyPrefixStable` defaults to `false` — the SAFE default. A caller that cannot prove
    /// the request's post-system prefix is byte-stable turn-over-turn (see
    /// `TrustedRouterPromptBuilder.assembled`) gets no annotation, because a moving prefix turns
    /// caching into a pure cache-WRITE premium.
    static func chatCompletionBody(
        model: String,
        messages: [[String: Any]],
        promptCachingPolicy: TrustedRouterPromptCachingPolicy = .automatic,
        historyPrefixStable: Bool = false
    ) throws -> Data {
        var body = TrustedRouterChatParameters.jsonObjectResponse
        body["model"] = model
        body["messages"] = TrustedRouterPromptCaching.annotatedMessages(
            messages,
            modelID: model,
            policy: promptCachingPolicy,
            historyPrefixStable: historyPrefixStable
        )
        body["stream"] = true
        body["stream_options"] = ["include_usage": true]
        return try JSONSerialization.data(withJSONObject: body)
    }

    /// The response headers as plain strings (`allHeaderFields` is `[AnyHashable: Any]`), for the
    /// rate-limit parser. Header-name case is preserved; the parser matches case-insensitively.
    private static func headerMap(_ response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String else { continue }
            headers[name] = "\(value)"
        }
        return headers
    }

    private static func drain(_ bytes: TrustedRouterByteStream) async throws -> String {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
