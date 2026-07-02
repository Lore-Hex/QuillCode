import XCTest
import QuillCodeCore
@testable import QuillCodeTools

final class WebSearchToolRouterTests: XCTestCase {
    func testWebSearchDefinitionIsRegistered() {
        let names = ToolRouter.definitions.map(\.name)
        XCTAssertTrue(names.contains(ToolDefinition.webSearch.name))
        XCTAssertEqual(Set(names).count, names.count, "tool names must stay unique")
    }

    func testWebSearchDefinitionShape() {
        let definition = ToolDefinition.webSearch
        XCTAssertEqual(definition.name, "host.web.search")
        XCTAssertEqual(definition.host, .local)
        XCTAssertEqual(definition.risk, .read)
        XCTAssertTrue(definition.parametersJSON.contains("\"query\""))
        XCTAssertTrue(definition.parametersJSON.contains("required"))
        // The schema must be valid JSON.
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(definition.parametersJSON.utf8)))
    }

    /// The synchronous router has no search client (search is async and routes through
    /// TrustedRouter in the agent loop), so a direct router dispatch must report search as
    /// unavailable rather than falling through to "Unknown tool".
    func testRouterReportsSearchUnavailableWithoutClient() {
        let router = ToolRouter(workspaceRoot: FileManager.default.temporaryDirectory)
        let result = router.execute(ToolCall(
            name: ToolDefinition.webSearch.name,
            argumentsJSON: #"{"query":"swift"}"#
        ))
        XCTAssertFalse(result.ok)
        XCTAssertTrue(result.error?.contains("not available") == true)
        XCTAssertFalse(result.error?.contains("Unknown tool") == true)
    }
}
