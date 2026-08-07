import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeAgent

final class AgentMissingDirectoryListPreflightTests: XCTestCase {
    func testMissingWorkspaceDirectoryIsDetectedButExistingAndOutsidePathsAreNot() throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("inputs"),
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            AgentMissingDirectoryListPreflight.missingPath(
                in: listCall("outputs"),
                workspaceRoot: root
            ),
            "outputs"
        )
        XCTAssertNil(AgentMissingDirectoryListPreflight.missingPath(
            in: listCall("inputs"),
            workspaceRoot: root
        ))
        XCTAssertNil(AgentMissingDirectoryListPreflight.missingPath(
            in: listCall("../outside"),
            workspaceRoot: root
        ))
    }

    func testMissingOutputListIsCorrectedBeforeExecution() async throws {
        let root = try makeTempDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let runner = AgentRunner(llm: SequenceLLMClient(actions: [
            .tool(listCall("outputs")),
            .tool(.init(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "outputs/report.md",
                    "content": "# Report\n\nDone.\n",
                ])
            )),
            .say("Created outputs/report.md."),
        ]))

        let result = try await runner.send(
            "Create outputs/report.md.",
            in: ChatThread(mode: .auto),
            workspaceRoot: root
        )

        XCTAssertEqual(result.toolResults.count, 1, "the missing list must not become a tool card")
        XCTAssertTrue(result.toolResults.allSatisfy(\.ok))
        XCTAssertTrue(result.thread.events.contains {
            $0.kind == .notice && $0.summary.contains("missing workspace directory")
        })
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("outputs/report.md").path
        ))
    }

    private func listCall(_ path: String) -> ToolCall {
        ToolCall(
            name: ToolDefinition.fileList.name,
            argumentsJSON: ToolArguments.json(["path": path])
        )
    }
}
