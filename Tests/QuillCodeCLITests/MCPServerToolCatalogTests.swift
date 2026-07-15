@testable import QuillCodeCLI
import XCTest

final class MCPServerToolCatalogTests: XCTestCase {
    func testCatalogExposesOnlyCodexCompatibleToolsAndSchemas() throws {
        let tools = try XCTUnwrap(
            MCPServerToolCatalog.listResult.objectValue?["tools"]?.arrayValue
        )
        XCTAssertEqual(tools.compactMap { $0.objectValue?["name"]?.stringValue }, [
            "codex", "codex-reply"
        ])

        let run = try XCTUnwrap(tools[0].objectValue)
        let runSchema = try XCTUnwrap(run["inputSchema"]?.objectValue)
        XCTAssertEqual(runSchema["additionalProperties"], .bool(false))
        XCTAssertEqual(runSchema["required"], .array([.string("prompt")]))
        let properties = try XCTUnwrap(runSchema["properties"]?.objectValue)
        XCTAssertEqual(Set(properties.keys), Set([
            "approval-policy", "base-instructions", "compact-prompt", "config", "cwd",
            "developer-instructions", "model", "prompt", "sandbox"
        ]))

        let reply = try XCTUnwrap(tools[1].objectValue)
        let replySchema = try XCTUnwrap(reply["inputSchema"]?.objectValue)
        XCTAssertEqual(replySchema["required"], .array([.string("prompt")]))
        XCTAssertNotNil(replySchema["properties"]?.objectValue?["conversationId"])
    }

    func testCallResultMirrorsTextInStructuredContent() throws {
        let threadID = UUID()
        let result = try XCTUnwrap(
            MCPServerToolCatalog.callResult(threadID: threadID, content: "done").objectValue
        )
        XCTAssertEqual(result["isError"], .bool(false))
        XCTAssertEqual(
            result["structuredContent"]?.objectValue?["threadId"]?.stringValue,
            threadID.uuidString.lowercased()
        )
        XCTAssertEqual(result["structuredContent"]?.objectValue?["content"], .string("done"))
        XCTAssertEqual(result["content"]?.arrayValue?.first?.objectValue?["text"], .string("done"))
    }

    func testToolInputRejectsUnknownArgumentsAndSupportsDeprecatedConversationID() throws {
        XCTAssertThrowsError(try MCPServerToolInvocation(params: .object([
            "name": .string("codex"),
            "arguments": .object(["prompt": .string("go"), "unknown": .bool(true)])
        ])))

        let id = UUID()
        let invocation = try MCPServerToolInvocation(params: .object([
            "name": .string("codex-reply"),
            "arguments": .object([
                "conversationId": .string(id.uuidString),
                "prompt": .string("continue")
            ])
        ]))
        XCTAssertEqual(invocation.threadID, id)
    }
}
