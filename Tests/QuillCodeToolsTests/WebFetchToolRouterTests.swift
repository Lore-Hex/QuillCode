import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class WebFetchToolRouterTests: XCTestCase {
    func testWebFetchDefinitionIsRegistered() {
        let names = ToolRouter.definitions.map(\.name)
        XCTAssertTrue(names.contains(ToolDefinition.webFetch.name))
        XCTAssertEqual(Set(names).count, names.count, "tool names must stay unique")
    }

    func testWebFetchDefinitionShape() {
        let definition = ToolDefinition.webFetch
        XCTAssertEqual(definition.name, "host.web.fetch")
        XCTAssertEqual(definition.host, .local)
        XCTAssertEqual(definition.risk, .read)
        XCTAssertTrue(definition.parametersJSON.contains("\"url\""))
        XCTAssertTrue(definition.parametersJSON.contains("\"query\""))
        XCTAssertTrue(definition.parametersJSON.contains("required"))
        // The schema must be valid JSON.
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(definition.parametersJSON.utf8)))
    }

    func testRouterDispatchesWebFetchCalls() throws {
        let client = StubWebFetchHTTPClient(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "text/html"],
                body: Data("<h1>Routed</h1>".utf8)
            )
        ])
        let router = ToolRouter(
            workspaceRoot: FileManager.default.temporaryDirectory,
            web: WebFetchToolExecutor(client: client)
        )
        let result = router.execute(ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: #"{"url":"https://example.com/page"}"#
        ))
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("# Routed"))
    }

    func testRouterPassesFocusedQueryToWebFetch() throws {
        let noise = (1...400).map { "<p>unrelated line \($0)</p>" }.joined()
        let client = StubWebFetchHTTPClient(responses: [
            WebFetchHTTPResponse(
                statusCode: 200,
                headerFields: ["content-type": "text/html"],
                body: Data((noise + "<p>Q4 revenue was $42 million.</p>").utf8)
            )
        ])
        let router = ToolRouter(
            workspaceRoot: FileManager.default.temporaryDirectory,
            web: WebFetchToolExecutor(client: client, outputMaxBytes: 2_000)
        )
        let result = router.execute(ToolCall(
            name: ToolDefinition.webFetch.name,
            argumentsJSON: #"{"url":"https://example.com/page","query":"Q4 revenue"}"#
        ))

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertTrue(result.stdout.contains("Q4 revenue was $42 million"))
        XCTAssertTrue(result.stdout.contains("Focused evidence windows for query: Q4 revenue"))
    }

    func testRouterRejectsMissingURLArgument() {
        let router = ToolRouter(
            workspaceRoot: FileManager.default.temporaryDirectory,
            web: WebFetchToolExecutor(client: StubWebFetchHTTPClient(responses: []))
        )
        let result = router.execute(ToolCall(name: ToolDefinition.webFetch.name, argumentsJSON: "{}"))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("url") == true)
    }
}
