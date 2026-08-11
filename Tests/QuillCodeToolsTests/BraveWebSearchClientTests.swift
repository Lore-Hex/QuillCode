import XCTest
@testable import QuillCodeTools

final class BraveWebSearchClientTests: XCTestCase {
    private static let fixtureHTML = """
    <nav><a href="https://brave.com/download/">Download Brave</a></nav>
    <div class="snippet svelte-a" data-pos="0" data-type="web" data-keynav="true">
      <div class="result-wrapper"><div class="result-content">
        <a href="https://example.com/first?a=1&amp;b=2" target="_self">
          <div class="site-name-wrapper">Example</div>
          <div class="title search-snippet-title line-clamp-1" title="First &amp; Best Result">ignored</div>
        </a>
        <div class="generic-snippet"><div class="content desktop-default-regular t-primary line-clamp-dynamic"><span>Today -</span> Useful <strong>grounded</strong> summary.</div></div>
      </div></div>
    </div>
    <div class="snippet svelte-a" data-pos="1" data-type="web" data-keynav="true">
      <div class="result-wrapper"><div class="result-content">
        <a href="https://example.org/review" target="_self">
          <div class="title search-snippet-title line-clamp-1">Second Review</div>
        </a>
        <div class="product-review"><div class="line-clamp-2">A creator&#39;s detailed review.</div></div>
      </div></div>
    </div>
    <footer><a href="https://brave.com/terms/">Terms</a></footer>
    """

    func testParsesOnlyOrganicWebResultBlocks() {
        let items = BraveWebSearchClient.parseResults(html: Self.fixtureHTML, maxResults: 10)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].url, "https://example.com/first?a=1&b=2")
        XCTAssertEqual(items[0].title, "First & Best Result")
        XCTAssertEqual(items[0].snippet, "Today - Useful grounded summary.")
        XCTAssertEqual(items[1].url, "https://example.org/review")
        XCTAssertEqual(items[1].title, "Second Review")
        XCTAssertEqual(items[1].snippet, "A creator's detailed review.")
    }

    func testRespectsLimitAndDeduplicatesURLs() {
        let items = BraveWebSearchClient.parseResults(
            html: Self.fixtureHTML + Self.fixtureHTML,
            maxResults: 1
        )
        XCTAssertEqual(items.map(\.url), ["https://example.com/first?a=1&b=2"])
    }

    func testRejectsInternalRelativeAndNonHTTPURLs() {
        XCTAssertNil(BraveWebSearchClient.validatedResultURL("https://search.brave.com/images"))
        XCTAssertNil(BraveWebSearchClient.validatedResultURL("https://cdn.search.brave.com/a"))
        XCTAssertNil(BraveWebSearchClient.validatedResultURL("/search?q=test"))
        XCTAssertNil(BraveWebSearchClient.validatedResultURL("javascript:alert(1)"))
        XCTAssertEqual(
            BraveWebSearchClient.validatedResultURL("https://example.net/page"),
            "https://example.net/page"
        )
    }

    func testUnparseableHTMLYieldsNoResults() {
        XCTAssertTrue(BraveWebSearchClient.parseResults(html: "<html></html>", maxResults: 5).isEmpty)
        XCTAssertTrue(BraveWebSearchClient.parseResults(html: Self.fixtureHTML, maxResults: 0).isEmpty)
    }

    private struct StubHTTPClient: WebFetchHTTPClient {
        var status: Int = 200
        var body = Data()

        func perform(_ request: WebFetchHTTPRequest) throws -> WebFetchHTTPResponse {
            WebFetchHTTPResponse(statusCode: status, body: body)
        }
    }

    func testSearchParsesThroughStubbedTransport() async throws {
        let client = BraveWebSearchClient(
            httpClient: StubHTTPClient(body: Data(Self.fixtureHTML.utf8))
        )
        let items = try await client.search(WebSearchRequest(query: "test query", maxResults: 5))
        XCTAssertEqual(items.count, 2)
    }

    func testNon2xxStatusThrowsTransportError() async {
        let client = BraveWebSearchClient(httpClient: StubHTTPClient(status: 429))
        do {
            _ = try await client.search(WebSearchRequest(query: "q", maxResults: 5))
            XCTFail("expected transport error")
        } catch let error as WebSearchClientError {
            guard case .transport = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
