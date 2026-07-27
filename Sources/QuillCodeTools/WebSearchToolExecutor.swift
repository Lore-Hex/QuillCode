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
    /// Probes candidate URLs and keeps only the ones that actually resolve. Injected (and
    /// optional) so the executor stays deterministic in tests; `nil` skips liveness filtering
    /// entirely (the pre-existing behavior). In production this is a `WebFetchURLLivenessChecker`,
    /// which is what stops the LLM-as-search-engine backend from surfacing hallucinated 404 URLs
    /// the model would otherwise fetch and cite.
    public var livenessChecker: (any WebSearchURLLivenessChecking)?
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
        livenessChecker: (any WebSearchURLLivenessChecking)? = nil,
        maxResults: Int = 10,
        defaultResults: Int = 5,
        maxQueryLength: Int = 400,
        maxTitleLength: Int = 200,
        maxSnippetLength: Int = 500
    ) {
        self.client = client
        self.livenessChecker = livenessChecker
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

        // Liveness filter: the search backend is a language model asked to act as a search engine,
        // so a fraction of the URLs it returns do not exist. Probe each one and keep only those that
        // resolve — the model must never receive (and then cite) a dead URL. `droppedUnreachable`
        // records how many were removed so a thin result set is not mistaken for "nothing found".
        let (live, droppedUnreachable) = await filterReachable(sanitized)
        guard !live.isEmpty else {
            return Self.failure("""
            Web search for \"\(query)\" found \(sanitized.count) candidate\(sanitized.count == 1 ? "" : "s"), \
            but none were reachable (every URL failed a liveness check — the search backend likely \
            returned URLs that do not exist). Rephrase the query, or open the browser pane with \
            host.browser.open for an interactive search. Do NOT cite a URL you could not open.
            """)
        }

        return ToolResult(ok: true, stdout: Self.render(
            query: query,
            results: live,
            droppedUnreachable: droppedUnreachable
        ))
    }

    /// Drops results whose URL does not resolve, preserving the original ranking of the survivors.
    /// Returns the live results and how many were dropped. With no injected checker, everything
    /// passes through unchanged (`0` dropped) — the pre-liveness behavior.
    func filterReachable(
        _ results: [WebSearchResultItem]
    ) async -> (live: [WebSearchResultItem], dropped: Int) {
        guard let livenessChecker else { return (results, 0) }
        let liveURLs = await livenessChecker.liveURLs(among: results.map(\.url))
        let live = results.filter { liveURLs.contains($0.url) }
        return (live, results.count - live.count)
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

    static func render(query: String, results: [WebSearchResultItem], droppedUnreachable: Int = 0) -> String {
        var lines: [String] = []
        lines.append("Search results for \"\(query)\" (\(results.count) result\(results.count == 1 ? "" : "s")). Use host.web.fetch on a URL to read the full page.")
        if droppedUnreachable > 0 {
            lines.append("(\(droppedUnreachable) other candidate URL\(droppedUnreachable == 1 ? " was" : "s were") dropped as unreachable — only URLs that resolved are listed. Cite only these.)")
        }
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
