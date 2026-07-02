import Foundation
import QuillCodeCore
import QuillCodeTools
import TrustedRouter

/// `WebSearchClient` routed through TrustedRouter.
///
/// TrustedRouter has no dedicated web-search endpoint and its OpenAI-compatible passthrough does
/// not forward provider-native search tools, so the reachable mechanism is a normal
/// `/chat/completions` request: we ask a current-knowledge model to act as a search engine and
/// return a strict JSON object of `{results: [{title, url, snippet}]}`. Provider selection stays
/// gateway-side (per issue #861) — we send a TrustedRouter model id and the gateway routes it. The
/// executor (`WebSearchToolExecutor`) then host-gates every returned URL and bounds the fields, so
/// the model's output is treated as untrusted and can only surface fetchable public URLs.
///
/// This type performs no direct URLSession/URLRequest work of its own (the TrustedRouter SDK owns
/// the transport), so it needs no FoundationNetworking import.
public struct TrustedRouterWebSearchClient: WebSearchClient {
    public var sessionStore: (any TrustedRouterSessionStore)?
    public var apiKeyOverride: String?
    public var model: String
    public var baseURL: String

    public init(
        sessionStore: (any TrustedRouterSessionStore)? = nil,
        apiKeyOverride: String? = nil,
        model: String = TrustedRouterDefaults.defaultModel,
        baseURL: String = TrustedRouterDefaults.defaultAPIBaseURL
    ) {
        self.sessionStore = sessionStore
        self.apiKeyOverride = apiKeyOverride
        self.model = model
        self.baseURL = baseURL
    }

    public func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem] {
        let apiKey: String
        do {
            apiKey = try configuredAPIKey()
        } catch {
            throw WebSearchClientError.missingAPIKey
        }

        let client: TrustedRouter
        do {
            client = try TrustedRouter(options: .init(apiKey: apiKey, baseUrl: baseURL))
        } catch {
            throw WebSearchClientError.transport(String(describing: error))
        }

        let completion: ChatCompletion
        do {
            completion = try await client.chatCompletions(
                model: model,
                messages: Self.messages(for: request),
                params: TrustedRouterChatParameters.jsonObjectResponse
            )
        } catch {
            throw WebSearchClientError.transport(String(describing: error))
        }

        guard let text = completion.choices.first?.message.content,
              text.contains(where: { !$0.isWhitespace })
        else {
            throw WebSearchClientError.emptyResponse
        }
        return Self.parseResults(text)
    }

    private func configuredAPIKey() throws -> String {
        try TrustedRouterAPIKeyResolver(
            sessionStore: sessionStore,
            apiKeyOverride: apiKeyOverride
        ).configuredAPIKey()
    }

    // MARK: - Prompt

    static func messages(for request: WebSearchRequest) -> [[String: Any]] {
        let system = """
        You are a web-search engine for a coding agent. For the user's query, return the most \
        relevant, currently-known public web pages. Respond with ONLY a JSON object of the form \
        {"results": [{"title": string, "url": string, "snippet": string}]}. Include at most \
        \(request.maxResults) results, ordered most relevant first. Every "url" MUST be a full \
        absolute https URL to a real public page (documentation, an official site, a reputable \
        reference); never invent URLs, and never use internal, localhost, or private-network \
        addresses. Keep each snippet to one or two sentences. If you do not know relevant pages, \
        return {"results": []}.
        """
        return [
            ["role": "system", "content": system],
            ["role": "user", "content": "Search query: \(request.query)"]
        ]
    }

    // MARK: - Parsing

    /// Defensive parse of the model's JSON. Tolerates fenced code blocks and surrounding prose by
    /// extracting the first balanced top-level object; missing/typo'd fields degrade to empty
    /// strings rather than throwing. The executor does the real validation (host-gating, caps), so
    /// this stays permissive and never force-unwraps.
    static func parseResults(_ text: String) -> [WebSearchResultItem] {
        guard let data = jsonObjectData(from: text),
              let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any]
        else {
            return []
        }
        guard let rawResults = object["results"] as? [Any] else {
            return []
        }
        var items: [WebSearchResultItem] = []
        for entry in rawResults {
            guard let dict = entry as? [String: Any] else { continue }
            let url = stringField(dict, "url")
            guard !url.isEmpty else { continue }
            items.append(WebSearchResultItem(
                title: stringField(dict, "title"),
                url: url,
                snippet: stringField(dict, "snippet")
            ))
        }
        return items
    }

    private static func stringField(_ dict: [String: Any], _ key: String) -> String {
        (dict[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Extract the JSON-object substring: prefer the whole trimmed string, but if the model wrapped
    /// it in ```json fences or prose, slice from the first `{` to the last `}`.
    private static func jsonObjectData(from text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) is [String: Any] {
            return data
        }
        guard let open = trimmed.firstIndex(of: "{"),
              let close = trimmed.lastIndex(of: "}"),
              open < close
        else {
            return nil
        }
        return String(trimmed[open...close]).data(using: .utf8)
    }
}
