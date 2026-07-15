import Foundation
import XCTest
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit
@testable import QuillCodeApp

@MainActor
final class WorkspaceWorkflowRecordingIntegrationTests: XCTestCase {
    func testStoppedRecordingReturnsToOriginAndCreatesSkillThroughAuditedTools() async throws {
        let workspace = try makeQuillCodeTestDirectory()
        let skillDirectory = workspace
            .appendingPathComponent(".quillcode/skills/publish-release", isDirectory: true)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        let skillContent = """
        ---
        name: publish-release
        description: Publish a tested release and verify the published version.
        ---

        # Publish a release

        ## When to use
        Use this skill to publish a tested release.

        ## Inputs
        - Version

        ## Steps
        1. Run the release checks.
        2. Publish the release.

        ## Verification
        Confirm the published version is visible.
        """
        let write = ToolCall(
            name: ToolDefinition.fileWrite.name,
            argumentsJSON: ToolArguments.json([
                "path": ".quillcode/skills/publish-release/SKILL.md",
                "content": skillContent
            ])
        )
        let project = ProjectRef(name: "Recorder", path: workspace.path)
        let origin = ChatThread(title: "Release workflow", projectID: project.id)
        let other = ChatThread(title: "Other task", projectID: project.id)
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(
                projects: [project],
                selectedProjectID: project.id,
                threads: [origin, other],
                selectedThreadID: other.id
            ),
            runner: AgentRunner(llm: WorkflowRecordingScriptedLLM(actions: [
                .tool(write),
                .say("Created the reusable publish-release skill.")
            ]))
        )
        let capture = WorkflowRecordingCapture(
            goal: "Publish a release",
            startedAt: Date(timeIntervalSince1970: 100),
            stoppedAt: Date(timeIntervalSince1970: 112),
            originThreadID: origin.id.uuidString,
            projectID: project.id.uuidString,
            workspaceRoot: workspace.path,
            events: [
                WorkflowRecordingEvent(
                    kind: .click,
                    elapsedMilliseconds: 1_000,
                    summary: "Clicked Publish."
                )
            ],
            snapshots: []
        )

        await model.submitWorkflowRecordingCapture(capture, workspaceRoot: workspace)

        XCTAssertEqual(model.selectedThread?.id, origin.id)
        XCTAssertEqual(
            try String(contentsOf: skillDirectory.appendingPathComponent("SKILL.md"), encoding: .utf8),
            skillContent
        )
        let updatedOrigin = try XCTUnwrap(model.root.threads.first { $0.id == origin.id })
        XCTAssertTrue(updatedOrigin.messages.contains {
            $0.role == .tool && $0.content.contains("Recorded actions:")
        })
        XCTAssertFalse(updatedOrigin.messages.contains {
            $0.role == .user && $0.content.contains("Recorded actions:")
        })
        XCTAssertTrue(updatedOrigin.messages.contains {
            $0.role == .user
                && $0.content == "Create the reusable skill from the workflow I just demonstrated."
        })
        XCTAssertEqual(updatedOrigin.messages.last?.content, "Created the reusable publish-release skill.")
        XCTAssertEqual(model.root.threads.first { $0.id == other.id }, other)
    }
}

private actor WorkflowRecordingScriptedLLM: LLMClient {
    private var actions: [AgentAction]

    init(actions: [AgentAction]) {
        self.actions = actions
    }

    func nextAction(
        thread: ChatThread,
        userMessage: String,
        tools: [ToolDefinition]
    ) async throws -> AgentAction {
        _ = thread
        _ = userMessage
        _ = tools
        guard !actions.isEmpty else { return .say("Done.") }
        return actions.removeFirst()
    }
}
