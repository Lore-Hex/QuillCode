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

    func testBrowserInspectFinalAnswerSummarizesPage() throws {
        let output = BrowserInspectionToolOutput(
            url: "http://localhost:5173",
            title: "Preview Page",
            status: "Preview ready",
            sourceLabel: "Local web app",
            inspectionDepth: .metadataOnly,
            summary: "Live DOM capture is not attached yet; QuillCode has URL metadata for this local page.",
            details: ["Host: localhost", "Scheme: HTTP", "Path: /"],
            outline: ["Page: localhost", "Path: /", "H1: Hero Preview"],
            textSnippet: "Hero Preview Buy now",
            comments: [
                .init(
                    url: "http://localhost:5173",
                    text: "Check the hero spacing",
                    createdAt: Date(timeIntervalSince1970: 0)
                )
            ]
        )
        let call = ToolCall(name: ToolDefinition.browserInspect.name, argumentsJSON: "{}")

        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: call,
            result: ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(output))
        )

        XCTAssertTrue(answer.contains("Inspected `Preview Page` at http://localhost:5173."))
        XCTAssertTrue(answer.contains("Inspection depth: Metadata only."))
        XCTAssertTrue(answer.contains("Outline: Page: localhost; Path: /; H1: Hero Preview."))
        XCTAssertTrue(answer.contains("Text: Hero Preview Buy now"))
        XCTAssertTrue(answer.contains("Browser comments: Check the hero spacing."))
    }

    func testApplyPatchFinalAnswerMentionsDiffRefreshFailure() throws {
        let call = ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": "diff --git a/a b/a\n"])
        )

        let answer = AgentFinalAnswerBuilder.finalAnswer(
            for: call,
            result: ToolResult(ok: true, stdout: "Patch applied.\n"),
            followUpReviewResult: ToolResult(ok: false, stderr: "not a git repository")
        )

        XCTAssertTrue(answer.contains("Patch applied"))
        XCTAssertTrue(answer.contains("could not refresh the review diff"))
        XCTAssertTrue(answer.contains("not a git repository"))
    }
}
