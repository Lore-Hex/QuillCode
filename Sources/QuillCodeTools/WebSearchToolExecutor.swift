import Foundation
import QuillCodeCore

/// Executes `host.web.search`: normalize and clamp the query + result count, ask the injected
/// `WebSearchClient` (TrustedRouter-backed in production), then defensively sanitize the results —
/// drop entries whose URL is not a fetchable public http(s) target (reusing `WebFetchHostGate`,
/// the same SSRF gate `host.web.fetch` applies), bound titles/snippets, de-duplicate by URL, and
/// cap the count. The model gets a compact, numbered list it can hand straight to `host.web.fetch`.
///
/// The client is injected behind a protocol so this whole path is deterministic in tests with a
/// scripted stub and never touches the network. Nothing here force-unwraps or does an unclamped
/// numeric conversion, so a hostile/empty/oversized result set degrades to a clear message.
public struct WebSearchToolExecutor: Sendable {
    public var client: any WebSearchClient
    /// Hard ceiling on results, independent of what the caller asks for or the provider returns.
    public var maxResults: Int
    /// Default result count when the caller omits `maxResults`.
    public var defaultResults: Int
    /// Longest query we forward; longer inputs are truncated so a runaway prompt can't be smuggled
    /// through the search box.
    public var maxQueryLength: Int
    /// Per-field display caps for untrusted, model-authored title/snippet text.
    public var maxTitleLength: Int
    public var maxSnippetLength: Int

    public init(
        client: any WebSearchClient,
        maxResults: Int = 10,
        defaultResults: Int = 5,
        maxQueryLength: Int = 400,
        maxTitleLength: Int = 200,
        maxSnippetLength: Int = 500
    ) {
        self.client = client
        self.maxResults = max(1, maxResults)
        self.defaultResults = min(max(1, defaultResults), max(1, maxResults))
        self.maxQueryLength = max(1, maxQueryLength)
        self.maxTitleLength = max(1, maxTitleLength)
        self.maxSnippetLength = max(1, maxSnippetLength)
    }

    public func search(query rawQuery: String, maxResults requested: Int?) async -> ToolResult {
        let query = Self.normalizedQuery(rawQuery, maxLength: maxQueryLength)
        guard !query.isEmpty else {
            return Self.failure("Provide a non-empty search query, e.g. \"URLSession follow redirects swift\".")
        }
        // Clamp the requested count into [1, maxResults] WITHOUT trusting the raw value: a negative
        // or absurd number becomes the default / the ceiling, never a huge allocation request.
        let count = Self.clampedCount(requested, defaultResults: defaultResults, maxResults: maxResults)

        let items: [WebSearchResultItem]
        do {
            items = try await client.search(WebSearchRequest(query: query, maxResults: count))
        } catch let error as WebSearchClientError {
            return Self.failure("Web search for \"\(query)\" failed: \(error.description).")
        } catch {
            return Self.failure("Web search for \"\(query)\" failed: \(error.localizedDescription)")
        }

        let sanitized = Self.sanitize(
            items,
            limit: count,
            maxTitleLength: maxTitleLength,
            maxSnippetLength: maxSnippetLength
        )
        guard !sanitized.isEmpty else {
            return Self.failure("""
            Web search for \"\(query)\" returned no usable results. Try rephrasing the query, or open \
            the browser pane with host.browser.open for an interactive search.
            """)
        }

        return ToolResult(ok: true, stdout: Self.render(query: query, results: sanitized))
    }

    // MARK: - Input normalization

    static func normalizedQuery(_ raw: String, maxLength: Int) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count > maxLength else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<end])
    }

    static func clampedCount(_ requested: Int?, defaultResults: Int, maxResults: Int) -> Int {
        guard let requested else { return defaultResults }
        return min(max(1, requested), maxResults)
    }

    // MARK: - Result sanitization

    static func sanitize(
        _ items: [WebSearchResultItem],
        limit: Int,
        maxTitleLength: Int,
        maxSnippetLength: Int
    ) -> [WebSearchResultItem] {
        var seen = Set<String>()
        var out: [WebSearchResultItem] = []
        for item in items {
            guard out.count < limit else { break }
            guard let url = fetchableURL(item.url) else { continue }
            let key = url.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(WebSearchResultItem(
                title: displayField(item.title, fallback: url, maxLength: maxTitleLength),
                url: url,
                snippet: displayField(item.snippet, fallback: "", maxLength: maxSnippetLength)
            ))
        }
        return out
    }

    /// Accept only absolute http(s) URLs that pass the SAME SSRF gate `host.web.fetch` uses, so a
    /// search hit can never surface (and then be fetched as) an internal/loopback/metadata target.
    /// Bare hosts are defaulted to https the way `WebFetchToolExecutor.normalizedRequestURL` does.
    static func fetchableURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host != nil else { return nil }
        guard WebFetchHostGate.blockReason(for: url) == nil else { return nil }
        return url.absoluteString
    }

    static func displayField(_ raw: String, fallback: String, maxLength: Int) -> String {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let text = collapsed.isEmpty ? fallback : collapsed
        guard text.count > maxLength else { return text }
        let end = text.index(text.startIndex, offsetBy: maxLength)
        return String(text[..<end]) + "…"
    }

    // MARK: - Rendering

    static func render(query: String, results: [WebSearchResultItem]) -> String {
        var lines: [String] = []
        lines.append("Search results for \"\(query)\" (\(results.count) result\(results.count == 1 ? "" : "s")). Use host.web.fetch on a URL to read the full page.")
        lines.append("")
        for (index, result) in results.enumerated() {
            lines.append("\(index + 1). \(result.title)")
            lines.append("   \(result.url)")
            if !result.snippet.isEmpty {
                lines.append("   \(result.snippet)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func failure(_ message: String) -> ToolResult {
        ToolResult(ok: false, error: message)
    }
}
