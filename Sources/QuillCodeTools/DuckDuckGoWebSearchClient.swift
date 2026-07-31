import Foundation

/// `WebSearchClient` backed by a REAL search engine: DuckDuckGo's no-JavaScript HTML endpoint
/// (`html.duckduckgo.com/html/?q=…`), fetched over the same SSRF-safe `WebFetchHTTPClient`
/// transport `host.web.fetch` uses.
///
/// This exists because the only previously-reachable search mechanism asked a language model to
/// ACT as a search engine, and a model with no live index cannot help but hallucinate plausible
/// URLs that 404 on fetch (F18: 11 of 13 fetched URLs dead, the report cited them anyway). Every
/// URL returned here was served by an actual index moments ago — grounded by construction, no API
/// key required, and it works identically in the GUI app and headless `exec` runs.
///
/// Parsing is a deliberately narrow string-scan (no DOM dependency): DuckDuckGo's HTML endpoint
/// renders each organic hit as an `<a class="result__a" href="…">title</a>` anchor plus a sibling
/// `result__snippet` element, with the destination wrapped in a `duckduckgo.com/l/?uddg=<encoded>`
/// redirect. Ads and internal links decode to duckduckgo.com hosts and are dropped. If the page
/// shape ever drifts, the scan finds no anchors and the caller's fallback chain takes over — the
/// failure mode is "no results", never wrong results.
public struct DuckDuckGoWebSearchClient: WebSearchClient {
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
        guard var components = URLComponents(string: "https://html.duckduckgo.com/html/") else {
            throw WebSearchClientError.transport("could not build DuckDuckGo search URL")
        }
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else {
            throw WebSearchClientError.transport("could not build DuckDuckGo search URL")
        }

        let httpRequest = WebFetchHTTPRequest(
            url: url,
            headers: WebFetchToolExecutor.browserLikeHeaders,
            timeout: timeout,
            // Results live in the first slice of the page; 512 KiB is several times a full page.
            maxBodyBytes: 512 * 1024
        )
        let response: WebFetchHTTPResponse
        do {
            // `perform` is blocking; hop off the cooperative pool like the liveness prober does.
            response = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(with: Result { try httpClient.perform(httpRequest) })
                }
            }
        } catch {
            throw WebSearchClientError.transport("DuckDuckGo search failed: \(error)")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw WebSearchClientError.transport(
                "DuckDuckGo search returned HTTP \(response.statusCode)"
            )
        }
        guard let html = String(data: response.body, encoding: .utf8), !html.isEmpty else {
            throw WebSearchClientError.emptyResponse
        }
        return Self.parseResults(html: html, maxResults: request.maxResults)
    }

    // MARK: - HTML parsing

    /// Scan for organic result anchors and their snippets. Tolerant of attribute order and
    /// whitespace; every extracted URL must decode to an absolute http(s) URL on a
    /// non-DuckDuckGo host or the hit is skipped.
    static func parseResults(html: String, maxResults: Int) -> [WebSearchResultItem] {
        var items: [WebSearchResultItem] = []
        var seenURLs = Set<String>()
        var cursor = html.startIndex

        while items.count < max(0, maxResults), cursor < html.endIndex {
            guard let anchorRange = html.range(of: "class=\"result__a\"", range: cursor..<html.endIndex) else {
                break
            }
            // The enclosing <a …> tag: back up to its "<a", then take through the closing "</a>".
            guard let tagStart = html.range(of: "<a ", options: .backwards, range: html.startIndex..<anchorRange.lowerBound),
                  let tagEnd = html.range(of: ">", range: anchorRange.upperBound..<html.endIndex),
                  let anchorClose = html.range(of: "</a>", range: tagEnd.upperBound..<html.endIndex)
            else {
                break
            }
            cursor = anchorClose.upperBound

            let tag = String(html[tagStart.lowerBound..<tagEnd.upperBound])
            let title = decodeText(String(html[tagEnd.upperBound..<anchorClose.lowerBound]))

            guard let href = attribute("href", in: tag),
                  let resolved = resolveResultURL(href),
                  seenURLs.insert(resolved).inserted
            else {
                continue
            }

            // Snippet: the next result__snippet element before the following result anchor.
            var snippet = ""
            let nextAnchor = html.range(of: "class=\"result__a\"", range: cursor..<html.endIndex)
            let snippetSearchEnd = nextAnchor?.lowerBound ?? html.endIndex
            if let snippetMark = html.range(of: "result__snippet", range: cursor..<snippetSearchEnd),
               let snippetTagEnd = html.range(of: ">", range: snippetMark.upperBound..<snippetSearchEnd),
               let snippetClose = html.range(of: "</", range: snippetTagEnd.upperBound..<snippetSearchEnd) {
                snippet = decodeText(String(html[snippetTagEnd.upperBound..<snippetClose.lowerBound]))
            }

            items.append(WebSearchResultItem(title: title, url: resolved, snippet: snippet))
        }
        return items
    }

    /// Extract a double-quoted attribute value from a single HTML tag string.
    static func attribute(_ name: String, in tag: String) -> String? {
        guard let nameRange = tag.range(of: name + "=\"") else { return nil }
        guard let close = tag.range(of: "\"", range: nameRange.upperBound..<tag.endIndex) else { return nil }
        return String(tag[nameRange.upperBound..<close.lowerBound])
    }

    /// DuckDuckGo wraps destinations as `//duckduckgo.com/l/?uddg=<pct-encoded>&rut=…`; decode the
    /// `uddg` parameter. Direct http(s) hrefs pass through. Anything that ends up relative, non-http,
    /// or still on a duckduckgo.com host (ads, internal pages) is rejected.
    static func resolveResultURL(_ rawHREF: String) -> String? {
        let href = decodeText(rawHREF)
        var candidate = href
        if let components = URLComponents(string: href.hasPrefix("//") ? "https:" + href : href),
           (components.host ?? "").hasSuffix("duckduckgo.com"),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            candidate = uddg
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty, !host.hasSuffix("duckduckgo.com")
        else {
            return nil
        }
        return candidate
    }

    /// Strip tags and unescape the entities DuckDuckGo's endpoint actually emits, collapsing runs
    /// of whitespace. Good enough for display strings — the executor bounds lengths downstream.
    static func decodeText(_ raw: String) -> String {
        var text = ""
        var insideTag = false
        for character in raw {
            if character == "<" { insideTag = true; continue }
            if character == ">" { insideTag = false; continue }
            if !insideTag { text.append(character) }
        }
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#x27;", "'"), ("&#39;", "'"), ("&nbsp;", " "),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
