import XCTest
import QuillCodeTools
@testable import QuillCodeAgent

/// Parsing tests for the TrustedRouter-backed web-search client. These exercise the defensive JSON
/// parse against clean, fenced, prose-wrapped, and hostile/malformed model output — no network.
final class TrustedRouterWebSearchClientTests: XCTestCase {
    func testCleanJSONObjectIsParsed() {
        let json = #"{"results":[{"title":"A","url":"https://a.com","snippet":"one"},{"title":"B","url":"https://b.com","snippet":"two"}]}"#
        let items = TrustedRouterWebSearchClient.parseResults(json)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "A")
        XCTAssertEqual(items[0].url, "https://a.com")
        XCTAssertEqual(items[1].snippet, "two")
    }

    func testFencedCodeBlockIsUnwrapped() {
        let json = """
        Here you go:
        ```json
        {"results":[{"title":"A","url":"https://a.com","snippet":"one"}]}
        ```
        """
        let items = TrustedRouterWebSearchClient.parseResults(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, "https://a.com")
    }

    func testMissingFieldsDegradeToEmptyStrings() {
        let json = #"{"results":[{"url":"https://a.com"}]}"#
        let items = TrustedRouterWebSearchClient.parseResults(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "")
        XCTAssertEqual(items[0].snippet, "")
    }

    func testEntryWithoutURLIsSkipped() {
        let json = #"{"results":[{"title":"no url"},{"title":"has url","url":"https://a.com"}]}"#
        let items = TrustedRouterWebSearchClient.parseResults(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "has url")
    }

    func testNonObjectEntriesAreIgnored() {
        let json = #"{"results":["a string", 42, null, {"url":"https://a.com"}]}"#
        let items = TrustedRouterWebSearchClient.parseResults(json)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, "https://a.com")
    }

    func testEmptyResultsArrayYieldsNoItems() {
        XCTAssertTrue(TrustedRouterWebSearchClient.parseResults(#"{"results":[]}"#).isEmpty)
    }

    func testGarbageInputYieldsNoItemsInsteadOfCrashing() {
        for hostile in ["", "not json at all", "{", "}", "[]", "null", #"{"results":"nope"}"#, #"{"wrong":[]}"#] {
            XCTAssertTrue(
                TrustedRouterWebSearchClient.parseResults(hostile).isEmpty,
                "hostile input \(hostile) must degrade to no results"
            )
        }
    }

    func testResultsWrappedInProseAreExtracted() {
        let text = "I found these: {\"results\":[{\"title\":\"A\",\"url\":\"https://a.com\",\"snippet\":\"s\"}]} — hope that helps!"
        let items = TrustedRouterWebSearchClient.parseResults(text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, "https://a.com")
    }

    func testPromptBoundsResultCountAndCarriesQuery() {
        let messages = TrustedRouterWebSearchClient.messages(
            for: WebSearchRequest(query: "swift concurrency", maxResults: 4)
        )
        XCTAssertEqual(messages.count, 2)
        let system = messages[0]["content"] as? String ?? ""
        XCTAssertTrue(system.contains("at most 4 results"))
        let user = messages[1]["content"] as? String ?? ""
        XCTAssertTrue(user.contains("swift concurrency"))
    }
}
