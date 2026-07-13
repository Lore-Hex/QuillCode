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

    func testApprovalGateRendersFocusedApproveAndSkipActionsWithoutToolArguments() throws {
        let runID = UUID().uuidString
        let gate = SubagentApprovalGate(
            runID: runID,
            requestID: "approval-123",
            toolName: "host.file.write",
            reason: "Confirm this workspace write."
        )
        let update = SubagentProgressUpdate(subagents: [
            SubagentProgressItem(
                name: "Builder",
                role: "Build the feature",
                status: .awaitingApproval,
                summary: "Waiting for approval",
                approvalGate: gate
            )
        ])
        let call = ToolCall(
            name: ToolDefinition.subagentsUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )
        let result = SubagentProgressToolExecutor.execute(call)
        let normalized = try JSONHelpers.decode(SubagentProgressUpdate.self, from: result.stdout)
        let thread = ChatThread(events: [ThreadEvent(
            kind: .toolCompleted,
            summary: "\(ToolDefinition.subagentsUpdate.name) completed",
            payloadJSON: try JSONHelpers.encodePretty(result)
        )])

        let item = try XCTUnwrap(SubagentProgressToolExecutor.activityItems(for: thread).first)

        XCTAssertEqual(normalized.subagents.first?.status, .awaitingApproval)
        XCTAssertEqual(item.statusLabel, "Needs approval")
        XCTAssertEqual(item.actions.map(\.title), ["Approve", "Skip"])
        XCTAssertEqual(
            WorkspaceSubagentApprovalCommand(commandID: item.actions[0].commandID)?.action,
            .approve
        )
        XCTAssertEqual(
            WorkspaceSubagentApprovalCommand(commandID: item.actions[1].commandID)?.action,
            .reject
        )
        let html = WorkspaceHTMLActivityPaneRenderer.render(WorkspaceActivitySurface(
            isVisible: true,
            subagents: [item]
        ))
        XCTAssertTrue(html.contains("Approve"))
        XCTAssertTrue(html.contains("Skip"))
        XCTAssertFalse(html.contains("argumentsJSON"))
    }

    func testMalformedOrDetachedApprovalGateCannotCreateAnAction() throws {
        let update = SubagentProgressUpdate(subagents: [
            SubagentProgressItem(
                name: "Builder",
                role: "Build the feature",
                status: .awaitingApproval,
                approvalGate: SubagentApprovalGate(
                    runID: "../../not-a-run",
                    requestID: "approval:with:separators",
                    toolName: "host.file.write",
                    reason: "Confirm this workspace write."
                )
            )
        ])
        let result = SubagentProgressToolExecutor.execute(ToolCall(
            name: ToolDefinition.subagentsUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        ))
        let normalized = try JSONHelpers.decode(SubagentProgressUpdate.self, from: result.stdout)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(normalized.subagents.first?.status, .blocked)
        XCTAssertNil(normalized.subagents.first?.approvalGate)
        let thread = ChatThread(events: [ThreadEvent(
            kind: .toolCompleted,
            summary: "\(ToolDefinition.subagentsUpdate.name) completed",
            payloadJSON: try JSONHelpers.encodePretty(result)
        )])
        XCTAssertTrue(SubagentProgressToolExecutor.activityItems(for: thread)[0].actions.isEmpty)
    }

    func testActivityKeepsEveryDurableRunAvailableForTranscriptDrilldown() {
        let threadID = UUID()
        let oldRun = SubagentRunRecord(
            id: UUID(),
            objective: "Older investigation",
            workers: [SubagentWorkerRecord(
                id: "old-worker",
                name: "Archivist",
                role: "inspect earlier behavior",
                status: .completed
            )],
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let newRun = SubagentRunRecord(
            id: UUID(),
            objective: "Current investigation",
            workers: [SubagentWorkerRecord(
                id: "new-worker",
                name: "Verifier",
                role: "verify current behavior",
                status: .running
            )],
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let thread = ChatThread(id: threadID, subagentRuns: [oldRun, newRun])
        let items = SubagentProgressToolExecutor.activityItems(for: thread)

        XCTAssertEqual(items.map(\.title), ["Verifier", "Archivist"])
        XCTAssertEqual(items.compactMap { $0.actions.first?.title }, ["View", "View"])
        XCTAssertEqual(
            items.compactMap { $0.actions.first?.commandID },
            [newRun, oldRun].map { run in
                WorkspaceSubagentTranscriptCommand.openCommandID(
                    parentThreadID: threadID,
                    runID: run.id,
                    workerID: run.workers[0].id
                )
            }
        )
    }
}
