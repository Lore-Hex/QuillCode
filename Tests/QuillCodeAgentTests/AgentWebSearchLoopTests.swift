import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

/// Records the query it was asked and replays a fixed result set, so the agent-loop wiring test is
/// deterministic and never touches the network.
private final class RecordingWebSearchClient: WebSearchClient, @unchecked Sendable {
    private let lock = NSLock()
    private let results: [WebSearchResultItem]
    private(set) var lastQuery: String?
    private(set) var lastMaxResults: Int?

    init(results: [WebSearchResultItem]) {
        self.results = results
    }

    func search(_ request: WebSearchRequest) async throws -> [WebSearchResultItem] {
        lock.withLock {
            lastQuery = request.query
            lastMaxResults = request.maxResults
        }
        return results
    }
}

final class AgentWebSearchLoopTests: XCTestCase {
    func testAgentDispatchesWebSearchToInjectedClient() async throws {
        let root = try makeTempDirectory()
        let client = RecordingWebSearchClient(results: [
            WebSearchResultItem(title: "URLSession docs", url: "https://developer.apple.com/urlsession", snippet: "The doc.")
        ])
        var runner = AgentRunner(
            llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.webSearch.name,
                argumentsJSON: #"{"query":"urlsession redirects","maxResults":3}"#
            )),
            safety: AlwaysApprovingSafetyReviewer()
        )
        runner.webSearch = client

        let result = try await runner.send(
            "how do redirects work",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(client.lastQuery, "urlsession redirects")
        XCTAssertEqual(client.lastMaxResults, 3)
        let first = try XCTUnwrap(result.toolResults.first)
        XCTAssertTrue(first.ok, first.error ?? "")
        XCTAssertTrue(first.stdout.contains("https://developer.apple.com/urlsession"))
    }

    func testAgentReportsSearchUnavailableWhenNoClientWired() async throws {
        let root = try makeTempDirectory()
        // No webSearch client on the runner (mock runtime), so the router's fallback message wins.
        let runner = AgentRunner(
            llm: FixedToolLLMClient(call: ToolCall(
                name: ToolDefinition.webSearch.name,
                argumentsJSON: #"{"query":"anything"}"#
            )),
            safety: AlwaysApprovingSafetyReviewer()
        )

        let result = try await runner.send(
            "search for something",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        let first = try XCTUnwrap(result.toolResults.first)
        XCTAssertFalse(first.ok)
        XCTAssertTrue(first.error?.contains("not available") == true)
    }
}
