import XCTest
@testable import QuillCodeApp
import QuillCodeTools

final class QuillCodeMCPSupportTests: XCTestCase {
    func testLifecycleStatusTitlesAndActiveFlags() {
        XCTAssertEqual(MCPServerLifecycleStatus.stopped.title, "Stopped")
        XCTAssertEqual(MCPServerLifecycleStatus.probing.title, "Probing")
        XCTAssertEqual(MCPServerLifecycleStatus.running.title, "Running")
        XCTAssertEqual(MCPServerLifecycleStatus.ready.title, "Ready")
        XCTAssertEqual(MCPServerLifecycleStatus.failed.title, "Failed")

        XCTAssertFalse(MCPServerLifecycleStatus.stopped.isActive)
        XCTAssertTrue(MCPServerLifecycleStatus.probing.isActive)
        XCTAssertTrue(MCPServerLifecycleStatus.running.isActive)
        XCTAssertTrue(MCPServerLifecycleStatus.ready.isActive)
        XCTAssertFalse(MCPServerLifecycleStatus.failed.isActive)
    }

    func testProbeSummaryBuildsDescriptorsFromLegacyToolNames() {
        let summary = MCPServerProbeSummary(
            serverName: "filesystem",
            serverVersion: "1.2.3",
            toolNames: ["read_file"],
            resourceNames: ["Docs"],
            promptNames: ["review"]
        )

        XCTAssertEqual(summary.serverLabel, "filesystem 1.2.3")
        XCTAssertEqual(summary.toolNames, ["read_file"])
        XCTAssertEqual(summary.toolDescriptors.map(\.name), ["read_file"])
        XCTAssertEqual(summary.toolCountLabel, "1 tool")
        XCTAssertEqual(summary.resourceCountLabel, "1 resource")
        XCTAssertEqual(summary.promptCountLabel, "1 prompt")
    }

    func testProbeSummaryKeepsDescriptorBackwardsCompatibilityOnDecode() throws {
        let legacyJSON = """
        {
          "toolNames": ["search", "read"],
          "resourceNames": ["docs"],
          "promptNames": []
        }
        """
        let summary = try JSONDecoder().decode(
            MCPServerProbeSummary.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(summary.toolNames, ["search", "read"])
        XCTAssertEqual(summary.toolDescriptors.map(\.name), ["search", "read"])
        XCTAssertEqual(summary.toolCountLabel, "2 tools")
    }

    func testProbeSummaryFromProbeResultPreservesDescriptorsAndLabels() {
        let result = MCPServerProbeResult(
            protocolVersion: "2024-11-05",
            serverName: "server",
            serverVersion: "2",
            toolDescriptors: [
                MCPToolDescriptor(
                    name: "lookup",
                    description: "Find things",
                    requiredArguments: ["query"],
                    optionalArguments: ["limit"],
                    schemaSummary: "query: string"
                )
            ],
            resourceNames: ["Guide"],
            resourceURIs: ["file:///guide.md"],
            promptNames: ["summarize"]
        )

        let summary = MCPServerProbeSummary(result: result)

        XCTAssertEqual(summary.protocolVersion, "2024-11-05")
        XCTAssertEqual(summary.serverLabel, "server 2")
        XCTAssertEqual(summary.toolNames, ["lookup"])
        XCTAssertEqual(summary.toolDescriptors.first?.requiredArguments, ["query"])
        XCTAssertEqual(summary.resourceURIs, ["file:///guide.md"])
        XCTAssertEqual(summary.promptNames, ["summarize"])
    }

    func testToolCallRequestAcceptsAliasesAndNestedArguments() throws {
        let request = try MCPToolCallRequest(argumentsJSON: """
        {
          "serverId": " filesystem ",
          "name": " read_file ",
          "arguments": {
            "path": "README.md",
            "line": 1
          }
        }
        """)

        XCTAssertEqual(request.serverID, "filesystem")
        XCTAssertEqual(request.toolName, "read_file")
        XCTAssertEqual(request.toolArgumentsJSON, #"{"line":1,"path":"README.md"}"#)
    }

    func testToolCallRequestPrefersExplicitArgumentsJSON() throws {
        let request = try MCPToolCallRequest(argumentsJSON: """
        {
          "serverID": "server",
          "toolName": "tool",
          "argumentsJSON": " { \\"raw\\": true } ",
          "arguments": { "ignored": true }
        }
        """)

        XCTAssertEqual(request.toolArgumentsJSON, #" { "raw": true } "#)
    }

    func testToolCallRequestReportsUsefulErrors() {
        XCTAssertThrowsError(try MCPToolCallRequest(argumentsJSON: "[]")) { error in
            XCTAssertEqual(String(describing: error), "MCP call arguments must be a JSON object.")
        }
        XCTAssertThrowsError(try MCPToolCallRequest(argumentsJSON: #"{"toolName":"read"}"#)) { error in
            XCTAssertEqual(String(describing: error), "MCP call requires a non-empty serverID.")
        }
        XCTAssertThrowsError(try MCPToolCallRequest(argumentsJSON: #"{"serverID":"server"}"#)) { error in
            XCTAssertEqual(String(describing: error), "MCP call requires a non-empty toolName.")
        }
    }

    func testResourceReadRequestAcceptsURIAndNameAliases() throws {
        let uriRequest = try MCPResourceReadRequest(argumentsJSON: """
        {
          "serverID": " docs ",
          "resourceURI": " file:///guide.md "
        }
        """)
        let nameRequest = try MCPResourceReadRequest(argumentsJSON: """
        {
          "serverId": " docs ",
          "name": "Guide"
        }
        """)

        XCTAssertEqual(uriRequest.serverID, "docs")
        XCTAssertEqual(uriRequest.resourceIdentifier, "file:///guide.md")
        XCTAssertEqual(nameRequest.serverID, "docs")
        XCTAssertEqual(nameRequest.resourceIdentifier, "Guide")
    }

    func testResourceReadRequestResolvesAdvertisedResourceNamesAndURIs() throws {
        let summary = MCPServerProbeSummary(
            resourceNames: ["Guide", "README"],
            resourceURIs: ["file:///guide.md", "file:///README.md"]
        )
        let nameRequest = try MCPResourceReadRequest(argumentsJSON: #"{"serverID":"docs","resourceName":"Guide"}"#)
        let uriRequest = try MCPResourceReadRequest(argumentsJSON: #"{"serverID":"docs","uri":"file:///README.md"}"#)
        let missingRequest = try MCPResourceReadRequest(argumentsJSON: #"{"serverID":"docs","name":"Missing"}"#)

        XCTAssertEqual(nameRequest.resourceURI(in: summary), "file:///guide.md")
        XCTAssertEqual(uriRequest.resourceURI(in: summary), "file:///README.md")
        XCTAssertNil(missingRequest.resourceURI(in: summary))
        XCTAssertNil(nameRequest.resourceURI(in: nil))
    }

    func testResourceReadRequestReportsUsefulErrors() {
        XCTAssertThrowsError(try MCPResourceReadRequest(argumentsJSON: "[]")) { error in
            XCTAssertEqual(String(describing: error), "MCP resource read arguments must be a JSON object.")
        }
        XCTAssertThrowsError(try MCPResourceReadRequest(argumentsJSON: #"{"resourceURI":"file:///guide.md"}"#)) { error in
            XCTAssertEqual(String(describing: error), "MCP resource read requires a non-empty serverID.")
        }
        XCTAssertThrowsError(try MCPResourceReadRequest(argumentsJSON: #"{"serverID":"docs"}"#)) { error in
            XCTAssertEqual(String(describing: error), "MCP resource read requires a non-empty resourceURI or resourceName.")
        }
    }

    func testPromptGetRequestAcceptsAliasesAndDefaultsArguments() throws {
        let request = try MCPPromptGetRequest(argumentsJSON: """
        {
          "serverId": " prompts ",
          "name": " summarize "
        }
        """)

        XCTAssertEqual(request.serverID, "prompts")
        XCTAssertEqual(request.promptName, "summarize")
        XCTAssertEqual(request.promptArgumentsJSON, "{}")
    }

    func testPromptGetRequestReportsUsefulErrors() {
        XCTAssertThrowsError(try MCPPromptGetRequest(argumentsJSON: "{}")) { error in
            XCTAssertEqual(String(describing: error), "MCP prompt get requires a non-empty serverID.")
        }
        XCTAssertThrowsError(try MCPPromptGetRequest(argumentsJSON: #"{"serverID":"server"}"#)) { error in
            XCTAssertEqual(String(describing: error), "MCP prompt get requires a non-empty promptName.")
        }
    }
}
