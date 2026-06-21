import Foundation
import XCTest
@testable import QuillCodeTools

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
        let input = Pipe()
        let output = Pipe()
        defer {
            try? input.fileHandleForWriting.close()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }

        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 1,
            "result": [
                "protocolVersion": "2024-11-05",
                "serverInfo": [
                    "name": "Fixture MCP",
                    "version": "1.0.0"
                ],
                "capabilities": [
                    "tools": [:]
                ]
            ]
        ]))
        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 2,
            "result": [
                "tools": [
                    [
                        "name": "read_file",
                        "description": "Read a file",
                        "inputSchema": ["type": "object"]
                    ],
                    [
                        "name": "write_file",
                        "inputSchema": ["type": "object"]
                    ]
                ]
            ]
        ]))
        try output.fileHandleForWriting.close()

        let result = try MCPStdioProber(
            standardInput: input.fileHandleForWriting,
            standardOutput: output.fileHandleForReading
        ).probe(timeout: 1.0)

        XCTAssertEqual(result.protocolVersion, "2024-11-05")
        XCTAssertEqual(result.serverName, "Fixture MCP")
        XCTAssertEqual(result.serverVersion, "1.0.0")
        XCTAssertEqual(result.toolNames, ["read_file", "write_file"])
        XCTAssertEqual(result.resourceNames, [])
        XCTAssertEqual(result.promptNames, [])
    }

    func testProbeReadsResourcesAndPromptsWhenAdvertised() throws {
        let input = Pipe()
        let output = Pipe()
        defer {
            try? input.fileHandleForWriting.close()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }

        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 1,
            "result": [
                "protocolVersion": "2024-11-05",
                "serverInfo": [
                    "name": "Fixture MCP",
                    "version": "1.0.0"
                ],
                "capabilities": [
                    "tools": [:],
                    "resources": [:],
                    "prompts": [:]
                ]
            ]
        ]))
        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 2,
            "result": [
                "tools": [
                    ["name": "read_file"]
                ]
            ]
        ]))
        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "resources": [
                    ["name": "README", "uri": "file:///workspace/README.md"],
                    ["uri": "file:///workspace/package.json"]
                ]
            ]
        ]))
        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 4,
            "result": [
                "prompts": [
                    ["name": "summarize_project"]
                ]
            ]
        ]))
        try output.fileHandleForWriting.close()

        let result = try MCPStdioProber(
            standardInput: input.fileHandleForWriting,
            standardOutput: output.fileHandleForReading
        ).probe(timeout: 1.0)

        XCTAssertEqual(result.toolNames, ["read_file"])
        XCTAssertEqual(result.resourceNames, ["README", "file:///workspace/package.json"])
        XCTAssertEqual(result.promptNames, ["summarize_project"])
    }

    func testCallToolSendsToolsCallAndParsesTextContent() throws {
        let input = Pipe()
        let output = Pipe()
        defer {
            try? input.fileHandleForWriting.close()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }

        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 1,
            "result": [
                "protocolVersion": "2024-11-05",
                "serverInfo": ["name": "Fixture MCP"],
                "capabilities": ["tools": [:]]
            ]
        ]))
        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 2,
            "result": [
                "tools": [["name": "read_file"]]
            ]
        ]))
        output.fileHandleForWriting.write(try MCPStdioMessageCodec.encodeJSONObject([
            "jsonrpc": "2.0",
            "id": 3,
            "result": [
                "content": [
                    ["type": "text", "text": "hello from MCP"]
                ],
                "isError": false
            ]
        ]))
        try output.fileHandleForWriting.close()

        let prober = MCPStdioProber(
            standardInput: input.fileHandleForWriting,
            standardOutput: output.fileHandleForReading
        )
        _ = try prober.probe(timeout: 1.0)
        let result = try prober.callTool(
            toolName: "read_file",
            argumentsJSON: #"{"path":"README.md"}"#,
            timeout: 1.0
        )

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(result.stdout, "hello from MCP")
    }
}
