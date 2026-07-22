import Foundation
import QuillCodeCore

// The default client is URLSession-backed, whose networking types live in FoundationNetworking
// on Linux (swift-corelibs-foundation) rather than Foundation.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Executes `host.web.fetch`: SSRF-gate the URL, GET it (following a bounded number of
/// redirects, re-gating every hop), retry once with browser-like headers when Cloudflare's
/// bot protection interferes, then decode and convert the body to markdown.
public struct WebFetchToolExecutor: Sendable {
    public var client: any WebFetchHTTPClient
    /// Streaming cap on the response body (~5 MB per the tool contract).
    public var maxBodyBytes: Int
    public var maxRedirects: Int
    /// Overall time budget per HTTP transaction, in seconds.
    public var timeout: TimeInterval
    /// Bounds on the markdown handed back to the model (ShellOutputCapper precedent).
    public var outputMaxLines: Int
    public var outputMaxBytes: Int

    public init(
        client: any WebFetchHTTPClient = URLSessionWebFetchHTTPClient(),
        maxBodyBytes: Int = 5_000_000,
        maxRedirects: Int = 5,
        timeout: TimeInterval = 25,
        outputMaxLines: Int = WebFetchMarkdownCapper.defaultMaxLines,
        outputMaxBytes: Int = WebFetchMarkdownCapper.defaultMaxBytes
    ) {
        self.client = client
        self.maxBodyBytes = max(1, maxBodyBytes)
        self.maxRedirects = max(0, maxRedirects)
        self.timeout = min(max(1, timeout), 120)
        self.outputMaxLines = max(1, outputMaxLines)
        self.outputMaxBytes = max(1024, outputMaxBytes)
    }

    public func fetch(urlString: String) -> ToolResult {
        guard let url = Self.normalizedRequestURL(urlString) else {
            return Self.failure(Self.invalidURLMessage(urlString))
        }

        let firstAttempt = performAttempt(startingAt: url, headers: Self.defaultHeaders)
        switch firstAttempt {
        case .success(let outcome):
            if let retryReason = Self.cloudflareBlockReason(outcome.response) {
                // Cloudflare bot heuristics often pass a browser-like client where a plain
                // tool UA is challenged; retry ONCE with browser headers before giving up.
                let secondAttempt = performAttempt(startingAt: url, headers: Self.browserLikeHeaders)
                switch secondAttempt {
                case .success(let retried):
                    if Self.cloudflareBlockReason(retried.response) != nil {
                        return Self.failure("""
                        \(retryReason) at \(outcome.finalURL.absoluteString), and a retry with browser-like \
                        headers was blocked too. This page needs a real browser — try host.browser.open \
                        with the same URL.
                        """)
                    }
                    return buildResult(requestedURL: url, outcome: retried)
                case .failure(let failure):
                    return Self.failure(failure.message)
                }
            }
            return buildResult(requestedURL: url, outcome: outcome)
        case .failure(let failure):
            return Self.failure(failure.message)
        }
    }

    // MARK: - Transport with redirect re-gating

    private struct AttemptOutcome {
        var response: WebFetchHTTPResponse
        var finalURL: URL
        var redirectCount: Int
    }

    private struct AttemptFailure: Error {
        var message: String

        init(_ message: String) {
            self.message = message
        }
    }

    private func performAttempt(
        startingAt url: URL,
        headers: [String: String]
    ) -> Result<AttemptOutcome, AttemptFailure> {
        var currentURL = url
        var redirectCount = 0
        while true {
            // EVERY hop goes through the SSRF gate — the initial URL and each redirect target.
            if let reason = WebFetchHostGate.blockReason(for: currentURL) {
                return .failure(AttemptFailure(
                    Self.blockedMessage(url: currentURL, reason: reason, wasRedirect: redirectCount > 0)
                ))
            }
            let response: WebFetchHTTPResponse
            do {
                response = try client.perform(WebFetchHTTPRequest(
                    url: currentURL,
                    headers: headers,
                    timeout: timeout,
                    maxBodyBytes: maxBodyBytes
                ))
            } catch let error as WebFetchHTTPClientError {
                return .failure(AttemptFailure("Fetching \(currentURL.absoluteString) failed: \(error.description)."))
            } catch {
                return .failure(AttemptFailure(
                    "Fetching \(currentURL.absoluteString) failed: \(error.localizedDescription)"
                ))
            }

            guard Self.isRedirect(response.statusCode) else {
                return .success(AttemptOutcome(
                    response: response,
                    finalURL: currentURL,
                    redirectCount: redirectCount
                ))
            }
            guard redirectCount < maxRedirects else {
                return .failure(AttemptFailure(Self.redirectLimitMessage(
                    maxRedirects: maxRedirects,
                    requestedURL: url,
                    currentURL: currentURL
                )))
            }
            guard let location = response.header("location")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !location.isEmpty,
                  let nextURL = URL(string: location, relativeTo: currentURL)?.absoluteURL
            else {
                return .failure(AttemptFailure(Self.missingLocationHeaderMessage(
                    url: currentURL,
                    statusCode: response.statusCode
                )))
            }
            currentURL = nextURL
            redirectCount += 1
        }
    }

    private static func isRedirect(_ statusCode: Int) -> Bool {
        // 304 has no Location and no body to follow; the other 3xx statuses are hops.
        (300..<400).contains(statusCode) && statusCode != 304
    }

    // MARK: - Result building

    private func buildResult(requestedURL: URL, outcome: AttemptOutcome) -> ToolResult {
        let response = outcome.response
        let finalURL = outcome.finalURL

        guard (200..<300).contains(response.statusCode) else {
            return Self.failure(Self.httpErrorMessage(statusCode: response.statusCode, url: finalURL))
        }
        if response.bodyExceededMaxBytes, response.body.isEmpty {
            return Self.failure("""
            \(finalURL.absoluteString) is larger than the \(Self.formatBytes(maxBodyBytes)) response cap. \
            Download it to a workspace file instead (host.shell.run with \
            curl -L --fail --output <file> '\(finalURL.absoluteString)').
            """)
        }

        let contentType = response.header("content-type")
        let classification = WebFetchResponseDecoder.classify(
            contentType: contentType,
            bodyPrefix: response.body.prefix(512)
        )
        if case .refused(let reportedType) = classification {
            return Self.failure("""
            \(finalURL.absoluteString) returned \(reportedType), which host.web.fetch cannot render as text. \
            Download it to a workspace file instead (host.shell.run with \
            curl -L --fail --output <file> '\(finalURL.absoluteString)').
            """)
        }

        let text = WebFetchResponseDecoder.decode(
            response.body,
            declaredCharset: WebFetchResponseDecoder.charset(of: contentType),
            sniffHTMLMeta: classification == .html
        )

        var content: String
        var converterTruncated = false
        let renderNote: String
        switch classification {
        case .html:
            let converted = HTMLToMarkdown.convert(text, options: HTMLToMarkdownOptions(
                baseURL: finalURL,
                maxOutputBytes: outputMaxBytes * 4
            ))
            content = converted.markdown
            converterTruncated = converted.truncated
            renderNote = "converted to markdown"
        case .passthroughText:
            content = text
            renderNote = "returned as-is"
        case .otherText:
            content = text
            renderNote = "textual content returned as-is"
        case .refused(let reportedType):
            // Already handled above; kept for exhaustiveness.
            return Self.failure(Self.refusedContentMessage(url: finalURL, reportedType: reportedType))
        }

        var truncationNotes: [String] = []
        if response.bodyExceededMaxBytes {
            truncationNotes.append(Self.responseCapNote(maxBodyBytes: maxBodyBytes, fetchedBytes: response.body.count))
        }
        let capped = WebFetchMarkdownCapper.cap(content, maxLines: outputMaxLines, maxBytes: outputMaxBytes)
        content = capped.text
        if converterTruncated, !capped.truncated {
            content += "\n\n[content truncated — the page was larger than the conversion budget]"
        }

        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            content = Self.emptyReadableContentPlaceholder
        }

        var summary = Self.fetchSummary(
            finalURL: finalURL,
            response: response,
            contentType: contentType,
            renderNote: renderNote
        )
        if outcome.redirectCount > 0 {
            summary += Self.redirectSummary(count: outcome.redirectCount, requestedURL: requestedURL)
        }
        for note in truncationNotes {
            summary += " Note: \(note)."
        }

        return ToolResult(ok: true, stdout: summary + "\n\n" + content)
    }

    // MARK: - Cloudflare detection

    /// Detects a Cloudflare bot-protection block. Anti-bot challenges answer 403 (and
    /// sometimes 503) with `cf-mitigated: challenge` or Cloudflare server markers.
    private static func cloudflareBlockReason(_ response: WebFetchHTTPResponse) -> String? {
        guard response.statusCode == 403 || response.statusCode == 503 else {
            return nil
        }
        if response.header("cf-mitigated") != nil {
            return "Cloudflare bot protection challenged the request (HTTP \(response.statusCode), cf-mitigated)"
        }
        let server = response.header("server")?.lowercased() ?? ""
        if server.contains("cloudflare"), response.header("cf-ray") != nil {
            return "Cloudflare blocked the request (HTTP \(response.statusCode))"
        }
        return nil
    }

    // MARK: - Helpers

    private static func invalidURLMessage(_ rawURL: String) -> String {
        "`\(rawURL)` is not a valid absolute http(s) URL. Pass a full URL like https://example.com/docs."
    }

    private static func normalizedRequestURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else {
            return nil
        }
        // Models sometimes pass bare hosts ("example.com/docs"); default them to https the
        // same way AgentDownloadRequestParser does. Anything scheme-ful is used as given —
        // the host gate rejects non-http(s) schemes with a clear message.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), url.host != nil else {
            return nil
        }
        return url
    }

    private static func blockedMessage(url: URL, reason: String, wasRedirect: Bool) -> String {
        let lead = wasRedirect
            ? "A redirect pointed at \(url.absoluteString), which is blocked"
            : "Refused to fetch \(url.absoluteString)"
        return "\(lead): \(reason). host.web.fetch only fetches public web hosts."
    }

    private static func httpErrorMessage(statusCode: Int, url: URL) -> String {
        var message = "\(url.absoluteString) answered HTTP \(statusCode)."
        switch statusCode {
        case 401, 403:
            message += " The page may require authentication or block automated clients — try host.browser.open."
        case 404:
            message += " Check the URL for typos or a moved page."
        case 429:
            message += " The server is rate limiting; wait before retrying."
        default:
            break
        }
        return message
    }

    private static func redirectLimitMessage(maxRedirects: Int, requestedURL: URL, currentURL: URL) -> String {
        "Gave up after \(maxRedirects) redirects fetching \(requestedURL.absoluteString); " +
            "the last hop was \(currentURL.absoluteString)."
    }

    private static func missingLocationHeaderMessage(url: URL, statusCode: Int) -> String {
        "\(url.absoluteString) answered HTTP \(statusCode) with a missing or unparseable Location header."
    }

    private static func refusedContentMessage(url: URL, reportedType: String) -> String {
        "\(url.absoluteString) returned \(reportedType), which host.web.fetch cannot render as text."
    }

    private static func responseCapNote(maxBodyBytes: Int, fetchedBytes: Int) -> String {
        "response body exceeded the \(formatBytes(maxBodyBytes)) cap; " +
            "only the first \(formatBytes(fetchedBytes)) were fetched"
    }

    private static func fetchSummary(
        finalURL: URL,
        response: WebFetchHTTPResponse,
        contentType: String?,
        renderNote: String
    ) -> String {
        let mimeType = contentType.map(WebFetchResponseDecoder.mimeType) ?? "no content type"
        return """
        Fetched \(finalURL.absoluteString) (HTTP \(response.statusCode), \(mimeType), \
        \(formatBytes(response.body.count)) fetched, \(renderNote)).
        """
    }

    private static func redirectSummary(count: Int, requestedURL: URL) -> String {
        " Followed \(count) redirect\(count == 1 ? "" : "s") from \(requestedURL.absoluteString)."
    }

    private static func failure(_ message: String) -> ToolResult {
        ToolResult(ok: false, error: message)
    }

    private static func formatBytes(_ count: Int) -> String {
        if count >= 1_000_000 {
            let megabytes = Double(count) / 1_000_000
            return String(format: "%.1f MB", megabytes)
        }
        if count >= 1_000 {
            return "\(count / 1_000) KB"
        }
        return "\(count) bytes"
    }

    private static let emptyReadableContentPlaceholder = """
    [the page had no readable text content — it likely renders via JavaScript; \
    try host.browser.open with the same URL]
    """

    /// Internal (not private) so the search liveness checker can probe with the EXACT same headers
    /// and two-attempt strategy `host.web.fetch` uses — otherwise a URL could pass a liveness probe
    /// under one User-Agent but 403 the real fetch under another (or vice-versa), making
    /// "probe-live" not imply "fetchable".
    static let defaultHeaders: [String: String] = [
        "Accept": "text/html, application/xhtml+xml;q=0.9, text/markdown;q=0.8, text/plain;q=0.7, */*;q=0.1",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "QuillCode/1.0 WebFetch (+https://lorehex.co)"
    ]

    static let browserLikeHeaders: [String: String] = [
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
    ]
}
