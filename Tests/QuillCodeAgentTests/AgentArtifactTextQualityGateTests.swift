import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentArtifactTextQualityGateTests: XCTestCase {
    func testDetectsVisibleEscapesButIgnoresCodeExamples() {
        XCTAssertTrue(AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
            content: "# Report\n\nLoop health:\\n- Activation is stable.\n",
            path: "outputs/report.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
            content: """
            # API

            Use `\\n` for a newline.

            ```swift
            let value = "\\n"
            ```
            """,
            path: "outputs/report.md"
        ))
        XCTAssertFalse(AgentArtifactTextQualityGate.containsMalformedLiteralEscape(
            content: "# Report\n\nLoop health:\n- Activation is stable.\n",
            path: "outputs/report.md"
        ))
    }

    func testMalformedNamedArtifactIsRewrittenBeforeReadbackAndCompletion() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let malformed = "# Report\n\nLoop health:\\n- Activation is stable.\n"
        let corrected = "# Report\n\nLoop health:\n- Activation is stable.\n"
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(writeCall(content: malformed)),
            .say("Created and verified outputs/report.md."),
            .tool(writeCall(content: corrected)),
            .say("Created outputs/report.md."),
            .say("Created and verified outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Create outputs/report.md. After writing, read the saved file back to verify it.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 3, "two writes and the forced final readback")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("clean text formatting")
        })
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("outputs/report.md"), encoding: .utf8),
            corrected
        )
    }

    private func writeCall(content: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": "outputs/report.md",
                "content": content,
            ])
        )
    }
}
