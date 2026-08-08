import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentInvalidShellProposalPreflightTests: XCTestCase {
    func testDetectsNonExecutableSourcePathAndUnavailableBareLabel() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("inputs/data.csv")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "name,value\nalpha,1\n".write(to: source, atomically: true, encoding: .utf8)

        XCTAssertNotNil(AgentInvalidShellProposalPreflight.correction(
            for: shellCall("inputs/data.csv"),
            workspaceRoot: root
        ))
        XCTAssertNotNil(AgentInvalidShellProposalPreflight.correction(
            for: shellCall("wave5_missing_data_label_8f149"),
            workspaceRoot: root
        ))
        XCTAssertNil(AgentInvalidShellProposalPreflight.correction(
            for: shellCall("printf"),
            workspaceRoot: root
        ))
        XCTAssertNil(AgentInvalidShellProposalPreflight.correction(
            for: shellCall("printf '%s' ok"),
            workspaceRoot: root
        ))
    }

    func testInvalidShellProposalAfterSourceReadIsCorrectedBeforeExecution() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("inputs/data.csv")
        try FileManager.default.createDirectory(
            at: source.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "name,value\nalpha,1\n".write(to: source, atomically: true, encoding: .utf8)

        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(.init(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": "inputs/data.csv"])
            )),
            .tool(shellCall("inputs/data.csv")),
            .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "outputs/report.md",
                    "content": "# Report\n\nValidated from the supplied source.\n",
                ])
            )),
            .say("Created outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Read inputs/data.csv and create outputs/report.md.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 2, "the invalid shell call must not execute")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("source path away from the shell")
        })
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("outputs/report.md").path
        ))
    }

    private func shellCall(_ command: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": command])
        )
    }
}
