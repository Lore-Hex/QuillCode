import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentFinalAnswerBuilderTests: XCTestCase {
    func testShellWhoamiAnswerIsSpecific() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "whoami"])
            ),
            result: ToolResult(ok: true, stdout: "quill\n")
        )

        XCTAssertEqual(answer, "You are `quill` in this workspace.")
    }

    func testOpenClawDiscoverySummarizesMissingBinary() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json([
                    "cmd": "command -v openclaw || which openclaw || echo 'not found'"
                ])
            ),
            result: ToolResult(ok: true, stdout: "not found\n")
        )

        XCTAssertEqual(answer, "openclaw is not installed or is not on PATH.")
    }

    func testLongOutputIsTruncatedWithToolCardHint() {
        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: ToolCall(
                name: ToolDefinition.shellRun.name,
                argumentsJSON: ToolArguments.json(["cmd": "printf long-output"])
            ),
            result: ToolResult(ok: true, stdout: String(repeating: "x", count: 2_100))
        )

        XCTAssertTrue(answer.contains("[truncated in chat; full output is in the tool card]"))
        XCTAssertLessThan(answer.count, 2_100)
    }
}
