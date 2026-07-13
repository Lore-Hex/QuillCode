import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceActivitySubagentIntegrationTests: XCTestCase {
    func testSubagentProgressToolRecordsVisibleActivityItems() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = SubagentProgressUpdate(
            objective: "  Split the validation pass across specialists.  ",
            subagents: [
                SubagentProgressItem(
                    name: "  Explorer  ",
                    role: "  Map the affected files.  ",
                    status: .completed,
                    summary: "  Activity and tool routing found.  ",
                    transcript: [
                        SubagentTranscriptEntry(
                            id: "tool-search",
                            kind: .tool,
                            title: "Search files",
                            detail: "Found sk-SYNTHETIC_ACTIVITY_SECRET_123456",
                            statusLabel: "Done"
                        ),
                        SubagentTranscriptEntry(
                            id: "response",
                            kind: .assistant,
                            title: "Response",
                            detail: "Mapped the Activity pane.",
                            statusLabel: "Answered"
                        )
                    ]
                ),
                SubagentProgressItem(
                    name: "Verifier",
                    role: "Run focused checks.",
                    status: .running,
                    summary: "Waiting on Swift tests."
                ),
                SubagentProgressItem(
                    name: "Frontend/UX",
                    role: "Inspect the interaction flow.",
                    status: .blocked,
                    summary: "Waiting on design notes.",
                    groupPath: ["Frontend"]
                )
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.subagentsUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(SubagentProgressUpdate.self, from: result.stdout)
        let subagentSection = try XCTUnwrap(model.surface().activity.sections.first { $0.kind == .subagents })

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.objective, "Split the validation pass across specialists.")
        XCTAssertEqual(decoded.subagents.map(\.name), ["Explorer", "Verifier", "Frontend/UX"])
        XCTAssertEqual(decoded.subagents[0].transcript.count, 2)
        XCTAssertTrue(decoded.subagents[0].transcript[0].detail.contains("[redacted]"))
        XCTAssertFalse(decoded.subagents[0].transcript[0].detail.contains("SYNTHETIC_ACTIVITY_SECRET"))
        XCTAssertEqual(decoded.subagents[2].groupPath, ["Frontend"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.subagentsUpdate.name) completed")
        XCTAssertEqual(model.surface().activity.subagents.map(\.title), ["Explorer", "Verifier", "UX"])
        XCTAssertEqual(model.surface().activity.subagents.map(\.statusLabel), ["Done", "Running", "Blocked"])
        XCTAssertEqual(model.surface().activity.subagents.map(\.kind), ["subagent", "subagent", "subagent"])
        XCTAssertEqual(model.surface().activity.subagents[0].transcript, decoded.subagents[0].transcript)
        XCTAssertTrue(model.surface().activity.subagents[0].detail.contains("Goal: Split the validation pass"))
        XCTAssertTrue(model.surface().activity.subagents[2].detail.contains("Path: Frontend / UX"))
        XCTAssertEqual(subagentSection.countLabel, "3 items")
        XCTAssertEqual(subagentSection.itemTestID, "activity-subagent")

        let threadJSON = try JSONHelpers.encodePretty(try XCTUnwrap(model.selectedThread))
        let restoredThread = try JSONHelpers.decode(ChatThread.self, from: threadJSON)
        XCTAssertEqual(SubagentProgressToolExecutor.activityItems(for: restoredThread)[0].transcript.count, 2)

        let html = WorkspaceHTMLActivityPaneRenderer.render(model.surface().activity)
        XCTAssertTrue(html.contains(#"data-testid="activity-subagent-transcript""#))
        XCTAssertTrue(html.contains(#"data-testid="activity-subagent-transcript-entry""#))
        XCTAssertTrue(html.contains("Search files"))
    }

    func testSubagentProgressToolRejectsEmptySubagents() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let call = ToolCall(
            name: ToolDefinition.subagentsUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(SubagentProgressUpdate(subagents: []))
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Subagent progress requires at least one subagent with a name and role.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }
}
