import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeTools

private final class MCPStdioProbeFixture {
    private let input = Pipe()
    private let output = Pipe()

    var prober: MCPStdioProber {
        MCPStdioProber(
            standardInput: input.fileHandleForWriting,
            standardOutput: output.fileHandleForReading
        )
    }

    func write(_ object: [String: Any]) throws {
        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject(object))
    }

    func writeInitialize(
        id: Int = 1,
        capabilities: [String: Any] = ["tools": [:]],
        serverInfo: [String: Any] = ["name": "Fixture MCP", "version": "1.0.0"]
    ) throws {
        try write([
            "jsonrpc": "2.0",
            "id": id,
            "result": [
                "protocolVersion": "2024-11-05",
                "serverInfo": serverInfo,
                "capabilities": capabilities
            ]
        ])
    }

    func writeTools(id: Int = 2, _ tools: [[String: Any]]) throws {
        try write([
            "jsonrpc": "2.0",
            "id": id,
            "result": ["tools": tools]
        ])
    }

    func finishWriting() throws {
        try output.fileHandleForWriting.close()
    }

    func readRequests() throws -> [[String: Any]] {
        try input.fileHandleForWriting.close()
        var data = input.fileHandleForReading.readDataToEndOfFile()
        var requests: [[String: Any]] = []
        while let message = try MCPStdioMessageCodec.nextMessageData(from: &data) {
            requests.append(try MCPStdioMessageCodec.decodeJSONObject(message))
        }
        XCTAssertTrue(data.isEmpty, "fixture should contain only complete MCP messages")
        return requests
    }

    func close() {
        try? input.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }
}

final class MCPStdioProberTests: XCTestCase {
    func testCodecEncodesAndParsesContentLengthMessages() throws {
        let first = try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 1,
            "result": ["ok": true]
        ])
        let second = try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 2,
            "result": ["tools": []]
        ])

        var buffer = Data()
        buffer.append(first.prefix(8))
        XCTAssertNil(try MCPStdioMessageCodec.nextMessageData(from: &buffer))
        buffer.append(first.dropFirst(8))
        buffer.append(second)

        let firstMessage = try XCTUnwrap(MCPStdioMessageCodec.nextMessageData(from: &buffer))
        let firstObject = try MCPStdioMessageCodec.decodeJSONObject(firstMessage)
        XCTAssertEqual(firstObject["id"] as? Int, 1)

        let secondMessage = try XCTUnwrap(MCPStdioMessageCodec.nextMessageData(from: &buffer))
        let secondObject = try MCPStdioMessageCodec.decodeJSONObject(secondMessage)
        XCTAssertEqual(secondObject["id"] as? Int, 2)
        XCTAssertTrue(buffer.isEmpty)
    }

    func testProbeReadsInitializeAndToolsListResponses() throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.writeInitialize()
        try fixture.writeTools([
            [
                "name": "read_file",
                "description": "Read a file",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"],
                        "encoding": ["type": "string"]
                    ],
                    "required": ["path"]
                ]
            ],
            [
                "name": "write_file",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": ["type": "string"],
                        "content": ["type": "string"],
                        "overwrite": ["type": "boolean"]
                    ],
                    "required": ["path", "content"]
                ]
            ]
        ])
        try fixture.finishWriting()

        let result = try fixture.prober.probe(timeout: 1.0)

        XCTAssertEqual(result.protocolVersion, "2024-11-05")
        XCTAssertEqual(result.serverName, "Fixture MCP")
        XCTAssertEqual(result.serverVersion, "1.0.0")
        XCTAssertEqual(
            result.serverInfo,
            .object(["name": .string("Fixture MCP"), "version": .string("1.0.0")])
        )
        XCTAssertEqual(result.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(result.tools.count, 2)
        XCTAssertEqual(result.tools[0].objectValue?["name"], .string("read_file"))
        XCTAssertEqual(result.tools[0].objectValue?["description"], .string("Read a file"))
        XCTAssertEqual(result.toolDescriptors.map(\.name), ["read_file", "write_file"])
        XCTAssertEqual(result.toolDescriptors[0].description, "Read a file")
        XCTAssertEqual(result.toolDescriptors[0].requiredArguments, ["path"])
        XCTAssertEqual(result.toolDescriptors[0].optionalArguments, ["encoding"])
        XCTAssertEqual(result.toolDescriptors[0].schemaSummary, "required: path:string; optional: encoding:string")
        XCTAssertEqual(result.toolDescriptors[1].requiredArguments, ["content", "path"])
        XCTAssertEqual(result.toolDescriptors[1].optionalArguments, ["overwrite"])
        XCTAssertEqual(
            result.toolDescriptors[1].schemaSummary,
            "required: content:string, path:string; optional: overwrite:boolean"
        )
        XCTAssertEqual(result.resourceNames, [])
        XCTAssertEqual(result.promptNames, [])
    }

    func testProbeReadsResourcesAndPromptsWhenAdvertised() throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.writeInitialize(capabilities: [
            "tools": [:],
            "resources": [:],
            "prompts": [:]
        ])
        try fixture.writeTools([["name": "read_file"]])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "resources": [
                    ["name": "README", "uri": "file:///workspace/README.md"],
                    ["uri": "file:///workspace/package.json"]
                ]
            ]
        ])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 4,
            "result": [
                "resourceTemplates": [
                    ["name": "Workspace file", "uriTemplate": "file:///{path}"]
                ]
            ]
        ])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 5,
            "result": [
                "prompts": [
                    ["name": "summarize_project"]
                ]
            ]
        ])
        try fixture.finishWriting()

        let result = try fixture.prober.probe(timeout: 1.0)

        XCTAssertEqual(result.toolNames, ["read_file"])
        XCTAssertEqual(result.resourceNames, ["README", "file:///workspace/package.json"])
        XCTAssertEqual(result.resourceURIs, ["file:///workspace/README.md", "file:///workspace/package.json"])
        XCTAssertEqual(result.resources.count, 2)
        XCTAssertEqual(result.resources[0].objectValue?["name"], .string("README"))
        XCTAssertEqual(result.resourceTemplates.count, 1)
        XCTAssertEqual(
            result.resourceTemplates[0].objectValue?["uriTemplate"],
            .string("file:///{path}")
        )
        XCTAssertEqual(result.promptNames, ["summarize_project"])
    }

    func testToolsAndAuthOnlyProbeSkipsResourceAndPromptInventory() throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.writeInitialize(capabilities: [
            "tools": [:],
            "resources": [:],
            "prompts": [:]
        ])
        try fixture.writeTools([["name": "read_file"]])
        try fixture.finishWriting()

        let result = try fixture.prober.probe(detail: .toolsAndAuthOnly, timeout: 1.0)
        let methods = try fixture.readRequests().compactMap { $0["method"] as? String }

        XCTAssertEqual(methods, ["initialize", "notifications/initialized", "tools/list"])
        XCTAssertEqual(result.toolNames, ["read_file"])
        XCTAssertTrue(result.resources.isEmpty)
        XCTAssertTrue(result.resourceTemplates.isEmpty)
        XCTAssertTrue(result.promptNames.isEmpty)
    }

    func testCallToolSendsToolsCallAndParsesTextContent() throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.writeInitialize(serverInfo: ["name": "Fixture MCP"])
        try fixture.writeTools([["name": "read_file"]])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "content": [
                    ["type": "text", "text": "hello from MCP"]
                ],
                "isError": false
            ]
        ])
        try fixture.finishWriting()

        let prober = fixture.prober
        _ = try prober.probe(timeout: 1.0)
        let result = try prober.callTool(
            toolName: "read_file",
            argumentsJSON: #"{"path":"README.md"}"#,
            timeout: 1.0
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "hello from MCP")
    }

    func testCallToolResultPreservesStructuredContentErrorAndMetadata() throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.writeInitialize(serverInfo: ["name": "Fixture MCP"])
        try fixture.writeTools([["name": "search"]])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "content": [["type": "text", "text": "partial result"]],
                "structuredContent": ["matches": 2, "query": "swift"],
                "isError": true,
                "_meta": ["traceID": "trace-123"]
            ]
        ])
        try fixture.finishWriting()

        let prober = fixture.prober
        _ = try prober.probe(timeout: 1.0)
        let result = try prober.callToolResult(
            toolName: "search",
            arguments: .object(["query": .string("swift")]),
            metadata: .object(["requestID": .string("request-123")]),
            timeout: 1.0
        )
        let call = try XCTUnwrap(
            fixture.readRequests().first { ($0["method"] as? String) == "tools/call" }
        )
        let params = try XCTUnwrap(call["params"] as? [String: Any])
        let arguments = try XCTUnwrap(params["arguments"] as? [String: Any])
        let metadata = try XCTUnwrap(params["_meta"] as? [String: Any])

        XCTAssertEqual(result.content, [.object(["text": .string("partial result"), "type": .string("text")])])
        XCTAssertEqual(
            result.structuredContent,
            .object(["matches": .number(2), "query": .string("swift")])
        )
        XCTAssertEqual(result.isError, true)
        XCTAssertEqual(result.metadata, .object(["traceID": .string("trace-123")]))
        XCTAssertEqual(arguments["query"] as? String, "swift")
        XCTAssertEqual(metadata["requestID"] as? String, "request-123")
    }

    func testCallToolEventsStreamsMatchingProgressBeforeFinalResult() async throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.write(progressNotification(token: "other", progress: 1, total: 100))
        try fixture.write(progressNotification(token: "progress-1", progress: 10, total: 100, message: "Indexing"))
        try fixture.write(progressNotification(token: "progress-1", progress: 10, total: 100, message: "Duplicate"))
        try fixture.write(progressNotification(token: "progress-1", progress: 75, total: 100, message: "Writing"))
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 1,
            "result": ["content": [["type": "text", "text": "complete"]], "isError": false]
        ])
        try fixture.finishWriting()

        var progress: [ToolExecutionProgress] = []
        var result: MCPToolCallResult?
        for try await event in fixture.prober.callToolEvents(
            toolName: "search",
            arguments: .object(["query": .string("swift")]),
            metadata: .object([
                "requestID": .string("request-1"),
                "progressToken": .string("progress-1")
            ]),
            timeout: 1.0
        ) {
            switch event {
            case .progress(let update): progress.append(update)
            case .result(let final): result = final
            }
        }

        XCTAssertEqual(progress, [
            .init(completed: 10, total: 100, message: "Indexing"),
            .init(completed: 75, total: 100, message: "Writing")
        ])
        XCTAssertEqual(result?.content.first?.objectValue?["text"], .string("complete"))
        let request = try XCTUnwrap(fixture.readRequests().first)
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        let metadata = try XCTUnwrap(params["_meta"] as? [String: Any])
        XCTAssertEqual(metadata["requestID"] as? String, "request-1")
        XCTAssertEqual(metadata["progressToken"] as? String, "progress-1")
    }

    func testCallToolEventsAddsUniqueProgressTokenWhenCallerOmitsOne() async throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 1,
            "result": ["content": [], "isError": false]
        ])
        try fixture.finishWriting()

        for try await _ in fixture.prober.callToolEvents(
            toolName: "search",
            arguments: nil,
            metadata: .object(["requestID": .string("request-2")]),
            timeout: 1.0
        ) {}

        let request = try XCTUnwrap(fixture.readRequests().first)
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        let metadata = try XCTUnwrap(params["_meta"] as? [String: Any])
        XCTAssertEqual(metadata["requestID"] as? String, "request-2")
        XCTAssertTrue((metadata["progressToken"] as? String)?.hasPrefix("quillcode-") == true)
    }

    func testReadResourceSendsResourcesReadAndParsesTextContent() throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.writeInitialize(
            capabilities: ["tools": [:], "resources": [:]],
            serverInfo: ["name": "Fixture MCP"]
        )
        try fixture.writeTools([])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "resources": [
                    ["name": "README", "uri": "file:///workspace/README.md"]
                ]
            ]
        ])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 4,
            "result": ["resourceTemplates": []]
        ])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 5,
            "result": [
                "contents": [
                    ["uri": "file:///workspace/README.md", "mimeType": "text/markdown", "text": "# README"]
                ]
            ]
        ])
        try fixture.finishWriting()

        let prober = fixture.prober
        let probe = try prober.probe(timeout: 1.0)
        let result = try prober.readResource(uri: "file:///workspace/README.md", timeout: 1.0)

        XCTAssertEqual(probe.resourceNames, ["README"])
        XCTAssertEqual(probe.resourceURIs, ["file:///workspace/README.md"])
        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "# README")
        XCTAssertEqual(result.artifacts, ["file:///workspace/README.md"])
    }

    func testGetPromptSendsPromptsGetAndParsesMessages() throws {
        let fixture = MCPStdioProbeFixture()
        defer { fixture.close() }

        try fixture.writeInitialize(
            capabilities: ["tools": [:], "prompts": [:]],
            serverInfo: ["name": "Fixture MCP"]
        )
        try fixture.writeTools([])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "prompts": [
                    ["name": "summarize_project"]
                ]
            ]
        ])
        try fixture.write([
            "jsonrpc": "2.0",
            "id": 4,
            "result": [
                "description": "Summarize the selected project.",
                "messages": [
                    [
                        "role": "user",
                        "content": ["type": "text", "text": "Summarize this project."]
                    ]
                ]
            ]
        ])
        try fixture.finishWriting()

        let prober = fixture.prober
        _ = try prober.probe(timeout: 1.0)
        let result = try prober.getPrompt(name: "summarize_project", timeout: 1.0)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(
            result.stdout,
            """
            Prompt: summarize_project
            Description: Summarize the selected project.
            user: Summarize this project.
            """
        )
    }

    private func progressNotification(
        token: Any,
        progress: Double,
        total: Double,
        message: String? = nil
    ) -> [String: Any] {
        var params: [String: Any] = [
            "progressToken": token,
            "progress": progress,
            "total": total
        ]
        if let message { params["message"] = message }
        return [
            "jsonrpc": "2.0",
            "method": "notifications/progress",
            "params": params
        ]
    }
}
