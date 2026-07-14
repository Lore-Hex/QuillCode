import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class ProjectPluginToolHookOutputParserTests: XCTestCase {
    func testPreToolUseParsesAllowRewriteContextAndWarning() throws {
        let output = try ProjectPluginToolHookOutputParser.parse(
            event: .preToolUse,
            result: ToolResult(
                ok: true,
                stdout: #"{"systemMessage":"check this","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"bounded","updatedInput":{"command":"printf rewritten"},"additionalContext":"private guidance"}}"#
            )
        )

        XCTAssertEqual(output.decision, .allow)
        XCTAssertEqual(output.decisionReason, "bounded")
        XCTAssertEqual(output.systemMessage, "check this")
        XCTAssertEqual(output.additionalContext, "private guidance")
        XCTAssertEqual(
            try jsonObject(try XCTUnwrap(output.updatedInputJSON))["command"] as? String,
            "printf rewritten"
        )
    }

    func testPreToolUseDenialSupportsNestedLegacyAndExitTwoForms() throws {
        let nested = try ProjectPluginToolHookOutputParser.parse(
            event: .preToolUse,
            result: ToolResult(
                ok: true,
                stdout: #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"not allowed"}}"#
            )
        )
        XCTAssertEqual(nested.decision, .deny)
        XCTAssertEqual(nested.decisionReason, "not allowed")

        let legacy = try ProjectPluginToolHookOutputParser.parse(
            event: .preToolUse,
            result: ToolResult(ok: true, stdout: #"{"decision":"block","reason":"legacy block"}"#)
        )
        XCTAssertEqual(legacy.decision, .deny)
        XCTAssertEqual(legacy.decisionReason, "legacy block")

        let exitTwo = try ProjectPluginToolHookOutputParser.parse(
            event: .preToolUse,
            result: ToolResult(ok: false, stderr: "stderr block", exitCode: 2)
        )
        XCTAssertEqual(exitTwo.decision, .deny)
        XCTAssertEqual(exitTwo.decisionReason, "stderr block")
    }

    func testPreToolUseUnsupportedControlsFailInsteadOfChangingExecution() {
        for stdout in [
            #"{"continue":false}"#,
            #"{"stopReason":"stop"}"#,
            #"{"suppressOutput":true}"#,
            #"{"decision":"approve"}"#,
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask"}}"#,
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"true"}}}"#
        ] {
            XCTAssertThrowsError(try ProjectPluginToolHookOutputParser.parse(
                event: .preToolUse,
                result: ToolResult(ok: true, stdout: stdout)
            ), stdout)
        }
    }

    func testPostToolUseParsesReplacementAndContextButIgnoresPlainStdout() throws {
        let block = try ProjectPluginToolHookOutputParser.parse(
            event: .postToolUse,
            result: ToolResult(
                ok: true,
                stdout: #"{"decision":"block","reason":"show this instead","hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"hidden context"}}"#
            )
        )
        XCTAssertEqual(block.replacementFeedback, "show this instead")
        XCTAssertEqual(block.additionalContext, "hidden context")

        let stopped = try ProjectPluginToolHookOutputParser.parse(
            event: .postToolUse,
            result: ToolResult(ok: true, stdout: #"{"continue":false,"stopReason":"done now"}"#)
        )
        XCTAssertEqual(stopped.replacementFeedback, "done now")

        XCTAssertEqual(
            try ProjectPluginToolHookOutputParser.parse(
                event: .postToolUse,
                result: ToolResult(ok: true, stdout: "ordinary output")
            ),
            ProjectPluginToolHookSemanticOutput()
        )
    }

    func testPostToolUseRejectsUnsupportedMutationFields() {
        for stdout in [
            #"{"suppressOutput":true}"#,
            #"{"updatedMCPToolOutput":{"value":1}}"#,
            #"{"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedInput":{}}}"#
        ] {
            XCTAssertThrowsError(try ProjectPluginToolHookOutputParser.parse(
                event: .postToolUse,
                result: ToolResult(ok: true, stdout: stdout)
            ), stdout)
        }
    }

    private func jsonObject(_ value: String) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        )
    }
}
