import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentOutsideWorkspaceShellPreflightTests: XCTestCase {
    func testOutsideWorkspaceTemporaryScriptIsCorrectedBeforeToolExecution() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shell-preflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let outside = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "cat > /tmp/analyze.py <<'PY'\nprint(1)\nPY"])
        )
        let workspaceLocal = ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": "python3 - <<'PY'\nprint(1)\nPY"])
        )
        let runner = AgentRunner(
            llm: SequenceLLMClient(actions: [
                .tool(outside),
                .tool(workspaceLocal),
                .say("Validated inside the workspace."),
            ]),
            safety: AlwaysApprovingSafetyReviewer(),
            toolExecutionOverride: { _, _ in ToolResult(ok: true, stdout: "1\n") }
        )

        let result = try await runner.send(
            "Validate the supplied workspace data with a temporary script.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1, "the unsafe proposal must not become a tool card")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertEqual(result.thread.messages.last?.content, "Validated inside the workspace.")
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("outside-workspace shell path")
        })
    }
}
