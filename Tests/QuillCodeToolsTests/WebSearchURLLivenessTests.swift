import XCTest
import QuillCodeCore
@testable import QuillCodeTools

/// A scripted liveness checker: exactly the URLs in `liveSet` are "reachable". Records what it was
/// asked to probe so tests can assert every candidate got checked. Never touches the network.
final class StubURLLivenessChecker: WebSearchURLLivenessChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let liveSet: Set<String>
    private var probed: [String] = []

    init(live: Set<String>) { self.liveSet = live }

    var probedURLs: [String] { lock.withLock { probed } }

    func liveURLs(among urls: [String]) async -> Set<String> {
        lock.withLock { probed.append(contentsOf: urls) }
        return liveSet.intersection(urls)
    }
}

final class WebSearchURLLivenessTests: XCTestCase {
    private func item(_ title: String, _ url: String) -> WebSearchResultItem {
        WebSearchResultItem(title: title, url: url, snippet: "snippet")
    }

    /// The core fix: a search that returns a mix of live and dead (hallucinated) URLs surfaces ONLY
    /// the live ones. The dead URLs never reach the model, so they can never be fetched or cited.
    func testOnlyLiveURLsSurface() async {
        let live = "https://www.jeffgeerling.com/"
        let client = StubWebSearchClient(results: [
            item("Dead review", "https://www.tomshardware.com/reviews/raspberry-pi-5-review"),
            item("Live blog", live),
            item("Dead product", "https://www.bee-link.com/products/beelink-mini-s12-pro"),
        ])
        let executor = WebSearchToolExecutor(
            client: client,
            livenessChecker: StubURLLivenessChecker(live: [live])
        )
        let result = await executor.search(query: "raspberry pi 5 vs n100", maxResults: nil)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains(live), "the live URL must be listed")
        XCTAssertFalse(result.stdout.contains("tomshardware"), "a dead URL must not be listed")
        XCTAssertFalse(result.stdout.contains("bee-link"), "a dead URL must not be listed")
        // The user-facing note tells the model results were dropped, so a thin list is not read as
        // "nothing found".
        XCTAssertTrue(result.stdout.contains("2 other candidate URLs were dropped as unreachable"))
    }

    /// When EVERY candidate is dead (the pure-hallucination case that broke use case #7), the tool
    /// fails with an explicit "none were reachable" message instead of handing the model dead URLs.
    func testAllDeadURLsFailsLoudly() async {
        let client = StubWebSearchClient(results: [
            item("Dead 1", "https://www.tomshardware.com/reviews/raspberry-pi-5-review"),
            item("Dead 2", "https://www.bee-link.com/products/beelink-mini-s12-pro"),
        ])
        let executor = WebSearchToolExecutor(
            client: client,
            livenessChecker: StubURLLivenessChecker(live: [])
        )
        let result = await executor.search(query: "q", maxResults: nil)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("none were reachable") == true, result.error ?? "")
        XCTAssertTrue(result.error?.contains("Do NOT cite a URL you could not open") == true)
    }

    /// Every candidate that survives host-gating must be probed — no silent skipping.
    func testAllCandidatesAreProbed() async {
        let checker = StubURLLivenessChecker(live: ["https://a.example/"])
        let client = StubWebSearchClient(results: [
            item("A", "https://a.example/"),
            item("B", "https://b.example/"),
        ])
        _ = await WebSearchToolExecutor(client: client, livenessChecker: checker)
            .search(query: "q", maxResults: nil)
        XCTAssertEqual(Set(checker.probedURLs), ["https://a.example/", "https://b.example/"])
    }

    /// Ranking of the survivors is preserved (liveness filtering must not reorder results).
    func testSurvivingOrderIsPreserved() async {
        let client = StubWebSearchClient(results: [
            item("first", "https://one.example/"),
            item("dead", "https://dead.example/"),
            item("second", "https://two.example/"),
        ])
        let executor = WebSearchToolExecutor(
            client: client,
            livenessChecker: StubURLLivenessChecker(live: ["https://one.example/", "https://two.example/"])
        )
        let out = await executor.search(query: "q", maxResults: nil)
        let firstIndex = out.stdout.range(of: "one.example")?.lowerBound
        let secondIndex = out.stdout.range(of: "two.example")?.lowerBound
        XCTAssertNotNil(firstIndex); XCTAssertNotNil(secondIndex)
        if let f = firstIndex, let s = secondIndex { XCTAssertTrue(f < s) }
    }

    /// With NO checker injected (mock/test runtime), results pass through unfiltered — the
    /// pre-liveness behavior is preserved exactly.
    func testNoCheckerLeavesResultsUnfiltered() async {
        let client = StubWebSearchClient(results: [
            item("Anything", "https://whatever.example/x"),
        ])
        let result = await WebSearchToolExecutor(client: client).search(query: "q", maxResults: nil)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("whatever.example"))
        XCTAssertFalse(result.stdout.contains("dropped as unreachable"))
    }
}

/// Unit tests for the real checker's status→reachable classification, driven by a stub HTTP client
/// so no network is touched.
final class WebFetchURLLivenessCheckerTests: XCTestCase {
    /// A stub `WebFetchHTTPClient` mapping URL → status code (or a thrown transport error).
    struct StubHTTPClient: WebFetchHTTPClient {
        var statusByHost: [String: Int]
        func perform(_ request: WebFetchHTTPRequest) throws -> WebFetchHTTPResponse {
            guard let host = request.url.host, let code = statusByHost[host] else {
                throw WebFetchHTTPClientError.transport("no route")
            }
            return WebFetchHTTPResponse(statusCode: code)
        }
    }

    private func checker(_ map: [String: Int]) -> WebFetchURLLivenessChecker {
        WebFetchURLLivenessChecker(httpClient: StubHTTPClient(statusByHost: map))
    }

    func test2xxAnd3xxAreLive_4xx5xxAndErrorsAreNot() async {
        let live = await checker([
            "ok.example": 200,
            "created.example": 201,
            "redirect.example": 301,
            "temp.example": 307,
            "notfound.example": 404,
            "gone.example": 410,
            "boom.example": 500,
        ]).liveURLs(among: [
            "https://ok.example/a",
            "https://created.example/a",
            "https://redirect.example/a",
            "https://temp.example/a",
            "https://notfound.example/a",
            "https://gone.example/a",
            "https://boom.example/a",
            "https://unreachable.example/a",   // stub throws (no mapping)
        ])
        XCTAssertEqual(live, [
            "https://ok.example/a",
            "https://created.example/a",
            "https://redirect.example/a",
            "https://temp.example/a",
        ])
    }

    func testEmptyInputReturnsEmpty() async {
        let live = await checker(["x.example": 200]).liveURLs(among: [])
        XCTAssertTrue(live.isEmpty)
    }
}
