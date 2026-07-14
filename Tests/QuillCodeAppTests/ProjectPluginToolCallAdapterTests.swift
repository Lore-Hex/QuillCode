import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

final class ProjectPluginToolCallAdapterTests: XCTestCase {
    func testShellAdapterUsesBashNameAndRewritesOnlyCommand() throws {
        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json([
                "cmd": "printf original",
                "timeoutSeconds": 9,
                "environment": ["SAFE": "value"]
            ])
        )
        let adapter = try XCTUnwrap(ProjectPluginToolCallAdapter.make(for: call))

        XCTAssertEqual(adapter.canonicalName, "Bash")
        XCTAssertEqual(adapter.aliases, ["Bash"])
        XCTAssertTrue(adapter.matches("^Bash$"))
        XCTAssertFalse(adapter.matches("^Write$"))

        let rewritten = try adapter.replacingToolInput(with: #"{"command":"printf rewritten","environment":{"BAD":"ignored"}}"#)
        let object = try jsonObject(rewritten.argumentsJSON)
        XCTAssertEqual(object["cmd"] as? String, "printf rewritten")
        XCTAssertEqual(object["timeoutSeconds"] as? Int, 9)
        XCTAssertEqual((object["environment"] as? [String: String])?["SAFE"], "value")
        XCTAssertNil((object["environment"] as? [String: String])?["BAD"])
        XCTAssertEqual(rewritten.id, call.id)
        XCTAssertEqual(rewritten.name, call.name)
    }

    func testPatchAliasesAndMCPNameAndReplacementArguments() throws {
        let patch = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": "old patch"])
        )
        let patchAdapter = try XCTUnwrap(ProjectPluginToolCallAdapter.make(for: patch))
        XCTAssertEqual(patchAdapter.canonicalName, "apply_patch")
        XCTAssertTrue(patchAdapter.matches("^(Edit|Write)$"))
        XCTAssertEqual(
            try jsonObject(patchAdapter.replacingToolInput(with: #"{"command":"new patch"}"#).argumentsJSON)["patch"] as? String,
            "new patch"
        )

        let mcp = ToolCall(
            name: ToolDefinition.mcpCall.name,
            argumentsJSON: ToolArguments.json([
                "serverID": "file system",
                "toolName": "read-file",
                "arguments": ["path": "before.txt"]
            ])
        )
        let mcpAdapter = try XCTUnwrap(ProjectPluginToolCallAdapter.make(for: mcp))
        XCTAssertEqual(mcpAdapter.canonicalName, "mcp__file_system__read-file")
        XCTAssertTrue(mcpAdapter.matches(#"^mcp__file_.*__read-file$"#))
        let rewrittenMCP = try jsonObject(
            mcpAdapter.replacingToolInput(with: #"{"path":"after.txt"}"#).argumentsJSON
        )
        XCTAssertEqual((rewrittenMCP["arguments"] as? [String: String])?["path"], "after.txt")
        XCTAssertEqual(rewrittenMCP["serverID"] as? String, "file system")
        XCTAssertEqual(rewrittenMCP["toolName"] as? String, "read-file")
    }

    func testMatcherValidationAndRewriteValidationAreFailClosed() throws {
        XCTAssertTrue(ProjectPluginToolCallAdapter.isValidMatcher(nil))
        XCTAssertTrue(ProjectPluginToolCallAdapter.isValidMatcher("*"))
        XCTAssertTrue(ProjectPluginToolCallAdapter.isValidMatcher("Bash|Write"))
        XCTAssertFalse(ProjectPluginToolCallAdapter.isValidMatcher("["))
        XCTAssertFalse(ProjectPluginToolCallAdapter.isValidMatcher(
            String(repeating: "x", count: ProjectPluginToolCallAdapter.maximumMatcherCharacters + 1)
        ))

        let call = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "true"])
        )
        let adapter = try XCTUnwrap(ProjectPluginToolCallAdapter.make(for: call))
        XCTAssertThrowsError(try adapter.replacingToolInput(with: #"{"cmd":"wrong-key"}"#)) {
            XCTAssertEqual($0 as? ProjectPluginToolCallAdapterError, .updatedCommandMissing)
        }
        XCTAssertThrowsError(try adapter.replacingToolInput(with: #"["not-an-object"]"#)) {
            XCTAssertEqual($0 as? ProjectPluginToolCallAdapterError, .updatedInputMustBeObject)
        }
    }

    private func jsonObject(_ value: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )
    }
}
