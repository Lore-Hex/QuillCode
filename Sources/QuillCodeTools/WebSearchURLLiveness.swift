import Foundation

/// Checks whether candidate search-result URLs actually resolve, so `host.web.search` can drop the
/// ones that don't before handing the list to the model.
///
/// This exists because the TrustedRouter-backed search asks a language model to ACT as a search
/// engine (TrustedRouter has no real search endpoint). A model with no live index cannot help but
/// hallucinate plausible URLs — `tomshardware.com/reviews/raspberry-pi-5-review`,
/// `jeffgeerling.com/blog/2023/raspberry-pi-5-vs-intel-n100`, … — that 404 the moment the agent
/// fetches them. Left unchecked the model then CITES those dead URLs. A cheap liveness probe turns
/// "validated guesses" into the only results the model ever sees: every surfaced URL was reachable
/// at search time.
public protocol WebSearchURLLivenessChecking: Sendable {
    /// Returns the subset of `urls` that responded with a reachable status. Order is irrelevant —
    /// the caller re-filters its own ordered list against this set. Must never throw: an
    /// unreachable/erroring URL is simply absent from the result.
    func liveURLs(among urls: [String]) async -> Set<String>
}

/// `WebSearchURLLivenessChecking` backed by the same SSRF-safe, redirect-refusing
/// `WebFetchHTTPClient` transport `host.web.fetch` uses. A URL counts as live when it answers with
/// a 2xx, or a 3xx (a redirect is a live target — the fetch tool re-gates the hop separately). The
/// probe reads at most a handful of body bytes and uses a short timeout, and the URLs are already
/// host-gated by `WebSearchToolExecutor.sanitize` before they arrive here.
public struct WebFetchURLLivenessChecker: WebSearchURLLivenessChecking {
    private let httpClient: any WebFetchHTTPClient
    private let timeout: TimeInterval

    public init(
        httpClient: any WebFetchHTTPClient = URLSessionWebFetchHTTPClient(),
        timeout: TimeInterval = 6
    ) {
        self.httpClient = httpClient
        self.timeout = max(1, timeout)
    }

    public func liveURLs(among urls: [String]) async -> Set<String> {
        guard !urls.isEmpty else { return [] }
        return await withTaskGroup(of: String?.self) { group in
            for url in urls {
                group.addTask { await self.isReachable(url) ? url : nil }
            }
            var live = Set<String>()
            for await result in group {
                if let url = result { live.insert(url) }
            }
            return live
        }
    }

    private func isReachable(_ raw: String) async -> Bool {
        guard let url = URL(string: raw), url.host != nil else { return false }
        // Probe with the SAME two-attempt header strategy host.web.fetch uses: the default UA first,
        // then the browser-like UA on a non-success status. A URL is "live" iff at least one of the
        // two header sets — the exact ones the real fetch will try — reaches it, so a surfaced URL
        // is genuinely fetchable and a browser-gated site is not falsely dropped.
        if await status(for: url, headers: WebFetchToolExecutor.defaultHeaders).map(Self.isReachableStatus) == true {
            return true
        }
        return await status(for: url, headers: WebFetchToolExecutor.browserLikeHeaders).map(Self.isReachableStatus) == true
    }

    private static func isReachableStatus(_ code: Int) -> Bool { (200..<400).contains(code) }

    private func status(for url: URL, headers: [String: String]) async -> Int? {
        let request = WebFetchHTTPRequest(
            url: url,
            headers: headers,
            timeout: timeout,
            // We only need the status line; a few bytes is plenty and keeps the probe cheap.
            maxBodyBytes: 64
        )
        // `perform` is blocking; run it off the cooperative pool so probing N URLs concurrently
        // never starves other async work.
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: (try? httpClient.perform(request))?.statusCode)
            }
        }
    }
}
