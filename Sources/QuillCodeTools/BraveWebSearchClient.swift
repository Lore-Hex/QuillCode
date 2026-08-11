import Foundation

/// `WebSearchClient` backed by Brave Search's server-rendered results page.
///
/// Brave emits each organic hit in a `data-type="web"` snippet with an absolute destination,
/// title, and summary. Parsing only those blocks avoids navigation, image, and promotional links.
/// If Brave changes the page shape, this client returns no results and the runtime's fallback
/// chain takes over.
public struct BraveWebSearchClient: WebSearchClient {
    private let httpClient: any WebFetchHTTPClient
    private let timeout: TimeInterval

    public init(
        httpClient: any WebFetchHTTPClient = URLSessionWebFetchHTTPClient(),
        timeout: TimeInterval = 12
    ) {
        self.httpClient = httpClient
        self.timeout = max(1, timeout)
    }

    public func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem] {
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        guard var components = URLComponents(string: "https://search.brave.com/search") else {
            throw WebSearchClientError.transport("could not build Brave search URL")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "source", value: "web"),
        ]
        guard let url = components.url else {
            throw WebSearchClientError.transport("could not build Brave search URL")
        }

        let httpRequest = WebFetchHTTPRequest(
            url: url,
            headers: WebFetchToolExecutor.browserLikeHeaders,
            timeout: timeout,
            maxBodyBytes: 1024 * 1024
        )
        let response: WebFetchHTTPResponse
        do {
            response = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result { try httpClient.perform(httpRequest) })
                }
            }
        } catch {
            throw WebSearchClientError.transport("Brave search failed: \(error)")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw WebSearchClientError.transport("Brave search returned HTTP \(response.statusCode)")
        }
        guard let html = String(data: response.body, encoding: .utf8), !html.isEmpty else {
            throw WebSearchClientError.emptyResponse
        }
        return Self.parseResults(html: html, maxResults: request.maxResults)
    }

    // MARK: - HTML parsing

    static func parseResults(html: String, maxResults: Int) -> [WebSearchResultItem] {
        var items: [WebSearchResultItem] = []
        var seenURLs = Set<String>()
        var cursor = html.startIndex

        while items.count < max(0, maxResults), cursor < html.endIndex {
            guard let typeMarker = html.range(
                of: "data-type=\"web\"",
                range: cursor..<html.endIndex
            ) else {
                break
            }
            let nextMarker = html.range(
                of: "data-type=\"web\"",
                range: typeMarker.upperBound..<html.endIndex
            )
            let blockEnd = nextMarker?.lowerBound ?? html.endIndex
            cursor = blockEnd

            guard let anchorStart = html.range(
                of: "<a ",
                range: typeMarker.upperBound..<blockEnd
            ), let anchorTagEnd = html.range(
                of: ">",
                range: anchorStart.upperBound..<blockEnd
            ) else {
                continue
            }
            let anchorTag = String(html[anchorStart.lowerBound..<anchorTagEnd.upperBound])
            guard let href = DuckDuckGoWebSearchClient.attribute("href", in: anchorTag),
                  let url = validatedResultURL(href),
                  seenURLs.insert(url).inserted
            else {
                continue
            }

            let title = extractTitle(
                html: html,
                range: anchorTagEnd.upperBound..<blockEnd
            )
            guard !title.isEmpty else { continue }
            let snippet = extractSnippet(
                html: html,
                range: anchorTagEnd.upperBound..<blockEnd
            )
            items.append(WebSearchResultItem(title: title, url: url, snippet: snippet))
        }
        return items
    }

    static func validatedResultURL(_ rawHREF: String) -> String? {
        let candidate = DuckDuckGoWebSearchClient.decodeText(rawHREF)
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty,
              host != "search.brave.com", !host.hasSuffix(".search.brave.com")
        else {
            return nil
        }
        return candidate
    }

    private static func extractTitle(
        html: String,
        range: Range<String.Index>
    ) -> String {
        guard let marker = html.range(of: "search-snippet-title", range: range),
              let tagStart = html.range(
                of: "<div ",
                options: .backwards,
                range: range.lowerBound..<marker.lowerBound
              ),
              let tagEnd = html.range(of: ">", range: marker.upperBound..<range.upperBound)
        else {
            return ""
        }
        let tag = String(html[tagStart.lowerBound..<tagEnd.upperBound])
        if let title = DuckDuckGoWebSearchClient.attribute("title", in: tag) {
            return DuckDuckGoWebSearchClient.decodeText(title)
        }
        guard let close = html.range(of: "</div>", range: tagEnd.upperBound..<range.upperBound) else {
            return ""
        }
        return DuckDuckGoWebSearchClient.decodeText(String(html[tagEnd.upperBound..<close.lowerBound]))
    }

    private static func extractSnippet(
        html: String,
        range: Range<String.Index>
    ) -> String {
        let classMarkers = [
            "content desktop-default-regular t-primary",
            "class=\"line-clamp-2\"",
        ]
        for classMarker in classMarkers {
            guard let marker = html.range(of: classMarker, range: range),
                  let tagEnd = html.range(of: ">", range: marker.upperBound..<range.upperBound),
                  let close = html.range(of: "</div>", range: tagEnd.upperBound..<range.upperBound)
            else {
                continue
            }
            return DuckDuckGoWebSearchClient.decodeText(
                String(html[tagEnd.upperBound..<close.lowerBound])
            )
        }
        return ""
    }
}
