import Foundation

/// A `WebSearchClient` that tries a grounded primary engine first and falls back to a secondary
/// only when the primary fails or finds nothing.
///
/// Runtime factories nest this type to try grounded search engines before the TrustedRouter
/// model-based client. Ordering is the point: real indexed results win, while guessed results are
/// consulted only when every grounded engine fails or returns nothing.
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
