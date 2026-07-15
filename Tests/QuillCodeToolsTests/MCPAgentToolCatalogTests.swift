import Foundation
import QuillCodeCore
@testable import QuillCodeTools
import XCTest

final class MCPAgentToolCatalogTests: XCTestCase {
    func testBuildsExactSchemasRoutesAndRiskFromRawMCPTools() throws {
        let catalog = MCPAgentToolCatalog(servers: [
            MCPAgentServerTools(serverName: "docs-server", tools: [
                .object([
                    "name": .string("search.docs"),
                    "description": .string("Search the documentation"),
                    "inputSchema": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("query")])
                    ]),
                    "annotations": .object(["readOnlyHint": .bool(true)])
                ]),
                .object([
                    "name": .string("remove"),
                    "annotations": .object(["destructiveHint": .bool(true)])
                ]),
                .object(["name": .string("append")])
            ])
        ])

        XCTAssertEqual(catalog.definitions.map(\.name), [
            "mcp__docs_server__append",
            "mcp__docs_server__remove",
            "mcp__docs_server__search_docs"
        ])
        XCTAssertEqual(catalog.definitions.map(\.risk), [.append, .destructive, .read])

        let search = try XCTUnwrap(catalog.definitions.last)
        XCTAssertEqual(search.host, .mcp)
        XCTAssertEqual(search.description, "Search the documentation")
        let schema = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(search.parametersJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(schema["type"] as? String, "object")
        XCTAssertEqual(schema["required"] as? [String], ["query"])

        XCTAssertEqual(
            catalog.route(forModelName: search.name),
            MCPAgentToolRoute(
                modelName: search.name,
                serverName: "docs-server",
                toolName: "search.docs"
            )
        )
    }

    func testAliasesAreDeterministicUniqueAndBoundedAcrossSanitizationCollisions() {
        let longTool = String(repeating: "long-tool-", count: 12)
        let servers = [
            MCPAgentServerTools(serverName: "some-server", tools: [
                .object(["name": .string("search")]),
                .object(["name": .string(longTool)])
            ]),
            MCPAgentServerTools(serverName: "some_server", tools: [
                .object(["name": .string("search")])
            ])
        ]

        let first = MCPAgentToolCatalog(servers: servers)
        let second = MCPAgentToolCatalog(servers: Array(servers.reversed()))
        let names = first.definitions.map(\.name)

        XCTAssertEqual(names, second.definitions.map(\.name))
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { $0.utf8.count <= MCPAgentToolCatalog.maximumModelNameBytes })
        XCTAssertEqual(names.filter { $0.hasPrefix("mcp__some_server__search__") }.count, 2)
        XCTAssertTrue(names.contains { $0.hasPrefix("mcp__some_server__long_tool_") && $0.contains("__") })

        let routes = first.routesByModelName.values
        XCTAssertEqual(Set(routes.map(\.serverName)), Set(["some-server", "some_server"]))
        XCTAssertTrue(routes.contains { $0.toolName == longTool })
    }

    func testIgnoresMalformedAndDuplicateToolsAndFallsBackToObjectSchema() {
        let catalog = MCPAgentToolCatalog(servers: [
            MCPAgentServerTools(serverName: "fixture", tools: [
                .object(["name": .string("ping")]),
                .object(["name": .string("ping"), "description": .string("duplicate")]),
                .object(["description": .string("missing name")]),
                .string("not a tool")
            ])
        ])

        XCTAssertEqual(catalog.definitions.count, 1)
        XCTAssertEqual(catalog.definitions[0].name, "mcp__fixture__ping")
        XCTAssertEqual(catalog.definitions[0].parametersJSON, #"{"properties":{},"type":"object"}"#)
        XCTAssertEqual(catalog.definitions[0].risk, .append)
    }
}
