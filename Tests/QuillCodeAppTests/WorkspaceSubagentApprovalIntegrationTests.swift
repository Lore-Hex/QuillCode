import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeSafety
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceSubagentApprovalIntegrationTests: XCTestCase {
    func testPausedWorkerSurvivesRelaunchAndCompletesExactApprovedTool() async throws {
        let workspace = try makeTempDirectory()
        let sessions = workspace.appendingPathComponent("subagent-sessions")
        let output = workspace.appendingPathComponent("approved.txt")
        let actions = SubagentApprovalActionQueue(actions: [
            .tool(ToolCall(
                name: ToolDefinition.fileWrite.name,
                argumentsJSON: ToolArguments.json([
                    "path": "approved.txt",
                    "content": "written exactly once"
                ])
            )),
            .say("Approved worker finished.")
        ])
        let runner = AgentRunner(
            llm: SubagentApprovalScriptedLLMClient(actions: actions),
            safety: StaticSafetyReviewer()
        )
        let model = QuillCodeWorkspaceModel(
            activity: ActivityState(isVisible: true),
            runner: runner,
            subagentSessionStoreDirectory: sessions
        )
        _ = model.newChat()
        model.setMode(.review)

        await model.runSubagentSlashCommand(
            WorkspaceSubagentRunRequest(
                objective: "Write a reviewed file",
                workers: [WorkspaceSubagentWorkerRequest(name: "Builder", role: "Write the requested file")]
            ),
            originalPrompt: "/subagents Write a reviewed file | Builder: Write the requested file",
            workspaceRoot: workspace
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let pausedItem = try XCTUnwrap(model.surface().activity.subagents.first)
        XCTAssertEqual(pausedItem.statusLabel, "Needs approval")
        let commandID = try XCTUnwrap(pausedItem.actions.first { $0.title == "Approve" }?.commandID)
        let command = try XCTUnwrap(WorkspaceSubagentApprovalCommand(commandID: commandID))
        XCTAssertNoThrow(try WorkspaceSubagentSessionStore(directory: sessions).load(command.runID))

        // Recreate the workspace model to prove the action resumes from the private journal rather
        // than process-local scheduler state.
        let relaunched = QuillCodeWorkspaceModel(
            root: model.root,
            activity: ActivityState(isVisible: true),
            runner: runner,
            subagentSessionStoreDirectory: sessions
        )
        await relaunched.resolveSubagentApproval(command, workspaceRoot: workspace)

        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "written exactly once")
        XCTAssertThrowsError(try WorkspaceSubagentSessionStore(directory: sessions).load(command.runID))
        let completedItem = try XCTUnwrap(relaunched.surface().activity.subagents.first)
        XCTAssertEqual(completedItem.statusLabel, "Done")
        XCTAssertTrue(completedItem.actions.isEmpty)
        XCTAssertEqual(
            relaunched.selectedThread?.messages.filter { $0.role == .user }.count,
            1,
            "Approval continuation must not duplicate the original delegated prompt."
        )
        XCTAssertTrue(completedItem.transcript.contains {
            $0.kind == .tool && $0.statusLabel == "Done"
        })
        XCTAssertTrue(completedItem.transcript.contains {
            $0.kind == .assistant && $0.detail.contains("Approved worker finished")
        })
    }
}

private actor SubagentApprovalActionQueue {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func next() -> AgentAction {
        guard !actions.isEmpty else { return .say("Done.") }
        return actions.removeFirst()
    }
}

private struct SubagentApprovalScriptedLLMClient: LLMClient {
    let actions: SubagentApprovalActionQueue

    func nextAction(
        thread _: ChatThread,
        userMessage _: String,
        tools _: [ToolDefinition]
    ) async throws -> AgentAction {
        await actions.next()
    }
}
