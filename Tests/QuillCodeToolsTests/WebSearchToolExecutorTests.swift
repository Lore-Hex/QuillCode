import XCTest
import QuillCodeCore
@testable import QuillCodeTools

/// Scripted `WebSearchClient` so executor tests are deterministic and never touch the network:
/// it replays one scripted outcome and records the request it was handed for inspection.
final class StubWebSearchClient: WebSearchClient, @unchecked Sendable {
    private let lock = NSLock()
    private let outcome: Result<[WebSearchResultItem], WebSearchClientError>
    private var recordedRequests: [WebSearchRequest] = []

    init(_ outcome: Result<[WebSearchResultItem], WebSearchClientError>) {
        self.outcome = outcome
    }

    convenience init(results: [WebSearchResultItem]) {
        self.init(.success(results))
    }

    var requests: [WebSearchRequest] {
        lock.withLock { recordedRequests }
    }

    func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem] {
        lock.withLock { recordedRequests.append(request) }
        return try outcome.get()
    }
}

final class WebSearchToolExecutorTests: XCTestCase {
    private func item(_ title: String, _ url: String, _ snippet: String = "snippet") -> WebSearchResultItem {
        WebSearchResultItem(title: title, url: url, snippet: snippet)
    }

    // MARK: - Happy path

    func testResultsAreRenderedWithNumberedURLs() async {
        let client = StubWebSearchClient(results: [
            item("Swift URLSession", "https://developer.apple.com/urlsession", "How to use URLSession."),
            item("Follow redirects", "https://stackoverflow.com/q/123", "Redirect handling.")
        ])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "urlsession redirects", maxResults: nil)
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("1. Swift URLSession"))
        XCTAssertTrue(result.stdout.contains("https://developer.apple.com/urlsession"))
        XCTAssertTrue(result.stdout.contains("2. Follow redirects"))
        XCTAssertTrue(result.stdout.contains("host.web.fetch"))
        XCTAssertTrue(result.stdout.contains("urlsession redirects"))
    }

    func testDefaultResultCountIsForwardedWhenOmitted() async {
        let client = StubWebSearchClient(results: [item("a", "https://a.com")])
        let executor = WebSearchToolExecutor(client: client, defaultResults: 5)
        _ = await executor.search(query: "hi", maxResults: nil)
        XCTAssertEqual(client.requests.first?.maxResults, 5)
    }

    // MARK: - Query normalization

    func testWhitespaceOnlyQueryIsRejectedWithoutCallingClient() async {
        let client = StubWebSearchClient(results: [item("x", "https://x.com")])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "   \n\t ", maxResults: nil)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(client.requests.isEmpty, "an empty query must not reach the search provider")
    }

    func testQueryWhitespaceIsCollapsed() async {
        let client = StubWebSearchClient(results: [item("x", "https://x.com")])
        let executor = WebSearchToolExecutor(client: client)
        _ = await executor.search(query: "  swift   async   await\n", maxResults: nil)
        XCTAssertEqual(client.requests.first?.query, "swift async await")
    }

    func testOverlongQueryIsTruncated() async {
        let client = StubWebSearchClient(results: [item("x", "https://x.com")])
        let executor = WebSearchToolExecutor(client: client, maxQueryLength: 10)
        _ = await executor.search(query: String(repeating: "a", count: 500), maxResults: nil)
        XCTAssertEqual(client.requests.first?.query.count, 10)
    }

    // MARK: - Result-count clamping

    func testRequestedCountIsClampedToCeiling() async {
        let client = StubWebSearchClient(results: [item("x", "https://x.com")])
        let executor = WebSearchToolExecutor(client: client, maxResults: 10)
        _ = await executor.search(query: "hi", maxResults: 9999)
        XCTAssertEqual(client.requests.first?.maxResults, 10)
    }

    func testNegativeCountFallsBackToOne() async {
        let client = StubWebSearchClient(results: [item("x", "https://x.com")])
        let executor = WebSearchToolExecutor(client: client, maxResults: 10)
        _ = await executor.search(query: "hi", maxResults: -5)
        XCTAssertEqual(client.requests.first?.maxResults, 1)
    }

    func testResultsAreTrimmedToRequestedCount() async {
        let client = StubWebSearchClient(results: (0..<10).map { item("t\($0)", "https://s\($0).com") })
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: 3)
        XCTAssertTrue(result.stdout.contains("3. t2"))
        XCTAssertFalse(result.stdout.contains("4. t3"), "must not render more than the requested count")
    }

    // MARK: - SSRF host gating of returned URLs

    func testInternalAndNonHTTPResultURLsAreDropped() async {
        let client = StubWebSearchClient(results: [
            item("metadata", "http://169.254.169.254/latest/meta-data/"),
            item("localhost", "http://localhost:8080/admin"),
            item("private", "http://10.0.0.5/router"),
            item("ftp", "ftp://example.com/file"),
            item("creds", "http://user:pass@example.com/"),
            item("good", "https://example.com/docs")
        ])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: 10)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("https://example.com/docs"))
        XCTAssertFalse(result.stdout.contains("169.254"))
        XCTAssertFalse(result.stdout.contains("localhost"))
        XCTAssertFalse(result.stdout.contains("10.0.0.5"))
        XCTAssertFalse(result.stdout.contains("ftp://"))
        XCTAssertFalse(result.stdout.contains("user:pass"))
    }

    func testAllResultsGatedAwayYieldsNoUsableResultsError() async {
        let client = StubWebSearchClient(results: [
            item("bad", "http://127.0.0.1/"),
            item("worse", "not a url")
        ])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: 10)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("no usable results") == true)
    }

    func testBareHostResultIsDefaultedToHTTPS() async {
        let client = StubWebSearchClient(results: [item("bare", "example.com/docs")])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: 10)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("https://example.com/docs"))
    }

    // MARK: - Dedup and field bounding

    func testDuplicateURLsAreDeduplicated() async {
        let client = StubWebSearchClient(results: [
            item("first", "https://example.com/page"),
            item("dup", "https://EXAMPLE.com/page"),
            item("other", "https://example.com/other")
        ])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: 10)
        XCTAssertTrue(result.stdout.contains("1. first"))
        XCTAssertTrue(result.stdout.contains("2. other"))
        XCTAssertFalse(result.stdout.contains("dup"))
    }

    func testEmptyTitleFallsBackToURL() async {
        let client = StubWebSearchClient(results: [item("", "https://example.com/x", "")])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: 10)
        XCTAssertTrue(result.ok)
        XCTAssertTrue(result.stdout.contains("1. https://example.com/x"))
    }

    func testOverlongTitleAndSnippetAreBounded() async {
        let client = StubWebSearchClient(results: [
            item(String(repeating: "T", count: 1000), "https://example.com/x", String(repeating: "S", count: 1000))
        ])
        let executor = WebSearchToolExecutor(client: client, maxTitleLength: 20, maxSnippetLength: 30)
        let result = await executor.search(query: "hi", maxResults: 10)
        XCTAssertTrue(result.ok)
        // Title capped at 20 chars + ellipsis; the 21st T must not appear as a run.
        XCTAssertFalse(result.stdout.contains(String(repeating: "T", count: 21)))
        XCTAssertFalse(result.stdout.contains(String(repeating: "S", count: 31)))
        XCTAssertTrue(result.stdout.contains("…"))
    }

    // MARK: - Error mapping

    func testMissingAPIKeyErrorIsSurfaced() async {
        let client = StubWebSearchClient(.failure(.missingAPIKey))
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: nil)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("not configured") == true)
    }

    func testTransportErrorIsSurfaced() async {
        let client = StubWebSearchClient(.failure(.transport("upstream 503")))
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "hi", maxResults: nil)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("upstream 503") == true)
    }

    func testEmptyResultListYieldsNoResultsMessage() async {
        let client = StubWebSearchClient(results: [])
        let executor = WebSearchToolExecutor(client: client)
        let result = await executor.search(query: "obscure query", maxResults: nil)
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("no usable results") == true)
        XCTAssertTrue(result.error?.contains("host.browser.open") == true)
    }
}
