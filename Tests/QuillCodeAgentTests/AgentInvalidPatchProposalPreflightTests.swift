import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentInvalidPatchProposalPreflightTests: XCTestCase {
    func testDistinguishesNoOpFromMeaningfulCodexEnvelopePatch() {
        let noOp = patchCall("""
        *** Begin Patch
        *** Update File: outputs/report.md
        @@
        -same line
        +same line
        *** End Patch
        """)
        let meaningful = patchCall("""
        *** Begin Patch
        *** Update File: outputs/report.md
        @@
        -before
        +after
        *** End Patch
        """)

        XCTAssertTrue(
            AgentInvalidPatchProposalPreflight.correction(for: noOp)?.prompt.contains("no change") == true
        )
        XCTAssertTrue(
            AgentInvalidPatchProposalPreflight.correction(for: meaningful)?.prompt.contains("raw git unified diff") == true
        )
    }

    func testNoOpCodexEnvelopeIsCorrectedBeforeExecution() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("outputs/report.md")
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Report\n\nDone.\n".write(to: output, atomically: true, encoding: .utf8)

        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": "outputs/report.md"])
            )),
            .tool(patchCall("""
            *** Begin Patch
            *** Update File: outputs/report.md
            @@
            -# Report
            +# Report
            *** End Patch
            """)),
            .say("Verified outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Read and verify outputs/report.md.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1, "the no-op patch must not become a tool card")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("would not change any bytes")
        })
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "# Report\n\nDone.\n")
    }

    private func patchCall(_ patch: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.applyPatch.name,
            argumentsJSON: ToolArguments.json(["patch": patch])
        )
    }
}
