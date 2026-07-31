import XCTest
@testable import QuillCodeTools

/// The grounded-search half of the F18 fix: parsing DuckDuckGo's HTML endpoint into real result
/// items, and the fallback composition that keeps the LLM-guess client as a last resort only.
final class DuckDuckGoWebSearchClientTests: XCTestCase {
    // A trimmed but shape-faithful slice of html.duckduckgo.com/html output: two organic results
    // (redirect-wrapped hrefs, entities, nested tags in titles/snippets) and one ad-ish internal
    // link that must be dropped.
    private static let fixtureHTML = """
    <div class="result results_links results_links_deep web-result ">
      <h2 class="result__title">
        <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.tomshardware.com%2Freviews%2Fraspberry%2Dpi%2D5&amp;rut=abc123">Raspberry Pi 5 Review: A New <b>Standard</b></a>
      </h2>
      <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.tomshardware.com%2Freviews%2Fraspberry%2Dpi%2D5&amp;rut=abc123">The Pi 5 is 2&#x27;s complement faster &amp; better than the Pi 4.</a>
    </div>
    <div class="result">
      <h2 class="result__title">
        <a rel="nofollow" class="result__a" href="https://www.pcmag.com/reviews/raspberry-pi-5">PCMag: Pi 5</a>
      </h2>
      <a class="result__snippet" href="https://www.pcmag.com/reviews/raspberry-pi-5">Direct-href result snippet.</a>
    </div>
    <div class="result result--ad">
      <a rel="nofollow" class="result__a" href="//duckduckgo.com/y.js?ad_provider=x">Sponsored thing</a>
    </div>
    """

    func testParsesRedirectWrappedAndDirectResults() {
        let items = DuckDuckGoWebSearchClient.parseResults(html: Self.fixtureHTML, maxResults: 10)
        XCTAssertEqual(items.count, 2, "two organic results; the ad/internal link is dropped")

        XCTAssertEqual(items[0].url, "https://www.tomshardware.com/reviews/raspberry-pi-5")
        XCTAssertEqual(items[0].title, "Raspberry Pi 5 Review: A New Standard")
        XCTAssertEqual(items[0].snippet, "The Pi 5 is 2's complement faster & better than the Pi 4.")

        XCTAssertEqual(items[1].url, "https://www.pcmag.com/reviews/raspberry-pi-5")
        XCTAssertEqual(items[1].title, "PCMag: Pi 5")
    }

    func testRespectsMaxResults() {
        let items = DuckDuckGoWebSearchClient.parseResults(html: Self.fixtureHTML, maxResults: 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, "https://www.tomshardware.com/reviews/raspberry-pi-5")
    }

    func testUnparseableHTMLYieldsNoResultsNotGarbage() {
        XCTAssertTrue(DuckDuckGoWebSearchClient.parseResults(html: "<html><body>nothing here</body></html>", maxResults: 5).isEmpty)
        XCTAssertTrue(DuckDuckGoWebSearchClient.parseResults(html: "", maxResults: 5).isEmpty)
    }

    func testResolveResultURLRejectsNonHTTPAndInternalHosts() {
        XCTAssertNil(DuckDuckGoWebSearchClient.resolveResultURL("//duckduckgo.com/y.js?ad_provider=x"))
        XCTAssertNil(DuckDuckGoWebSearchClient.resolveResultURL("javascript:alert(1)"))
        XCTAssertNil(DuckDuckGoWebSearchClient.resolveResultURL("/html/?q=next-page"))
        XCTAssertEqual(
            DuckDuckGoWebSearchClient.resolveResultURL("//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.org%2Fa%3Fb%3Dc&rut=zz"),
            "https://example.org/a?b=c"
        )
        XCTAssertEqual(
            DuckDuckGoWebSearchClient.resolveResultURL("http://example.org/plain"),
            "http://example.org/plain"
        )
    }

    func testDeduplicatesRepeatedURLs() {
        let doubled = Self.fixtureHTML + Self.fixtureHTML
        let items = DuckDuckGoWebSearchClient.parseResults(html: doubled, maxResults: 10)
        XCTAssertEqual(items.map(\.url), [
            "https://www.tomshardware.com/reviews/raspberry-pi-5",
            "https://www.pcmag.com/reviews/raspberry-pi-5",
        ])
    }

    // MARK: - Transport behavior (stubbed HTTP)

    private struct StubHTTPClient: WebFetchHTTPClient {
        var status: Int = 200
        var body: Data = Data()
        func perform(_ request: WebFetchHTTPRequest) throws -> WebFetchHTTPResponse {
            WebFetchHTTPResponse(statusCode: status, body: body)
        }
    }

    func testSearchParsesThroughStubbedTransport() async throws {
        let client = DuckDuckGoWebSearchClient(
            httpClient: StubHTTPClient(body: Data(Self.fixtureHTML.utf8))
        )
        let items = try await client.search(WebSearchRequest(query: "raspberry pi 5 review", maxResults: 5))
        XCTAssertEqual(items.count, 2)
    }

    func testNon2xxStatusThrowsTransportError() async {
        let client = DuckDuckGoWebSearchClient(httpClient: StubHTTPClient(status: 403))
        do {
            _ = try await client.search(WebSearchRequest(query: "q", maxResults: 5))
            XCTFail("expected transport error")
        } catch let error as WebSearchClientError {
            guard case .transport = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testEmptyQueryShortCircuitsWithoutNetwork() async throws {
        struct ExplodingClient: WebFetchHTTPClient {
            func perform(_ request: WebFetchHTTPRequest) throws -> WebFetchHTTPResponse {
                XCTFail("must not hit the network for an empty query")
                throw WebSearchClientError.emptyResponse
            }
        }
        let items = try await DuckDuckGoWebSearchClient(httpClient: ExplodingClient())
            .search(WebSearchRequest(query: "   ", maxResults: 5))
        XCTAssertTrue(items.isEmpty)
    }
}

final class FallbackWebSearchClientTests: XCTestCase {
    private struct ScriptedClient: WebSearchClient {
        var results: [WebSearchResultItem] = []
        var error: WebSearchClientError?
        func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem] {
            if let error { throw error }
            return results
        }
    }

    private static let hit = WebSearchResultItem(title: "t", url: "https://example.org", snippet: "s")
    private static let fallbackHit = WebSearchResultItem(title: "f", url: "https://fallback.example", snippet: "s")

    func testPrimaryResultsWinWithoutConsultingFallback() async throws {
        struct ExplodingFallback: WebSearchClient {
            func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem] {
                XCTFail("fallback must not run when the primary has results")
                return []
            }
        }
        let client = FallbackWebSearchClient(
            primary: ScriptedClient(results: [Self.hit]),
            fallback: ExplodingFallback()
        )
        let items = try await client.search(WebSearchRequest(query: "q", maxResults: 5))
        XCTAssertEqual(items, [Self.hit])
    }

    func testPrimaryErrorFallsBack() async throws {
        let client = FallbackWebSearchClient(
            primary: ScriptedClient(error: .transport("rate limited")),
            fallback: ScriptedClient(results: [Self.fallbackHit])
        )
        let items = try await client.search(WebSearchRequest(query: "q", maxResults: 5))
        XCTAssertEqual(items, [Self.fallbackHit])
    }

    func testPrimaryEmptyFallsBack() async throws {
        let client = FallbackWebSearchClient(
            primary: ScriptedClient(results: []),
            fallback: ScriptedClient(results: [Self.fallbackHit])
        )
        let items = try await client.search(WebSearchRequest(query: "q", maxResults: 5))
        XCTAssertEqual(items, [Self.fallbackHit])
    }

    func testBothFailingSurfacesThePrimaryError() async {
        let client = FallbackWebSearchClient(
            primary: ScriptedClient(error: .transport("primary down")),
            fallback: ScriptedClient(error: .missingAPIKey)
        )
        do {
            _ = try await client.search(WebSearchRequest(query: "q", maxResults: 5))
            XCTFail("expected error")
        } catch let error as WebSearchClientError {
            guard case .transport(let message) = error else { return XCTFail("wrong error: \(error)") }
            XCTAssertEqual(message, "primary down")
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }
}
