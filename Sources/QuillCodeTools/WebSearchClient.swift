import Foundation

/// One web-search request: a normalized query plus the maximum number of results to return.
/// The transport (see `WebSearchToolExecutor`) clamps `maxResults` into a sane band before it
/// reaches here, so an implementation may trust the value is small and positive.
public struct WebSearchRequest: Sendable, Hashable {
    public var query: String
    public var maxResults: Int

    public init(query: String, maxResults: Int) {
        self.query = query
        self.maxResults = maxResults
    }
}

/// A single search hit. `url` is an absolute http(s) URL the agent can hand straight to
/// `host.web.fetch`; `snippet` is a short extract. Titles/snippets are model-authored text and
/// are treated as untrusted display strings — the executor bounds their length.
public struct WebSearchResultItem: Sendable, Hashable {
    public var title: String
    public var url: String
    public var snippet: String

    public init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

public enum WebSearchClientError: Error, Sendable, CustomStringConvertible {
    /// No TrustedRouter API key was configured, so the search route is unreachable.
    case missingAPIKey
    /// The gateway answered but returned nothing usable (empty body / unparseable results).
    case emptyResponse
    /// The transport failed (HTTP error, network, decode). `message` is already human-readable.
    case transport(String)

    public var description: String {
        switch self {
        case .missingAPIKey:
            return "TrustedRouter is not configured. Sign in or set an API key to use web search."
        case .emptyResponse:
            return "the search provider returned no results"
        case .transport(let message):
            return message
        }
    }
}

/// A backend that turns a `WebSearchRequest` into a list of results. The concrete implementation
/// (`TrustedRouterWebSearchClient` in QuillCodeAgent) routes the query through TrustedRouter so
/// provider selection stays gateway-side; tests inject a scripted stub so the executor's parsing,
/// clamping, and host-gating are verified without any network I/O.
public protocol WebSearchClient: Sendable {
    func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem]
}
