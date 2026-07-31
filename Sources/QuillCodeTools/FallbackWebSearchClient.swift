import Foundation

/// A `WebSearchClient` that tries a grounded primary engine first and falls back to a secondary
/// only when the primary fails or finds nothing.
///
/// The intended composition (see the runtime factories) is
/// `primary = DuckDuckGoWebSearchClient` (a real index; can rate-limit or drift its HTML shape)
/// and `fallback = TrustedRouterWebSearchClient` (an LLM acting as a search engine; always
/// answers, but its URLs are guesses that survive only the downstream liveness filter). Ordering
/// is the point: real results when the real engine works, and the guessing client is only ever
/// consulted when the alternative is returning nothing at all.
public struct FallbackWebSearchClient: WebSearchClient {
    private let primary: any WebSearchClient
    private let fallback: any WebSearchClient

    public init(primary: any WebSearchClient, fallback: any WebSearchClient) {
        self.primary = primary
        self.fallback = fallback
    }

    public func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem] {
        let primaryError: any Error
        do {
            let results = try await primary.search(request)
            if !results.isEmpty { return results }
            primaryError = WebSearchClientError.emptyResponse
        } catch {
            primaryError = error
        }
        do {
            return try await fallback.search(request)
        } catch {
            // The primary's failure is the more informative one to surface: the fallback failing
            // usually just repeats a shared cause (offline, missing key).
            throw primaryError
        }
    }
}
