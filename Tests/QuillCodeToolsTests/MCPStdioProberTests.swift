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
    }
}
