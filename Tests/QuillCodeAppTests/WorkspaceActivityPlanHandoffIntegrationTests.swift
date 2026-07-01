import XCTest
import QuillCodeCore
import QuillCodeTools
@testable import QuillCodeApp

@MainActor
final class WorkspaceActivityPlanHandoffIntegrationTests: XCTestCase {
    func testActivitySurfacePrefersModelAuthoredPlan() throws {
        let update = AgentPlanUpdate(
            explanation: "The model is planning the work directly.",
            plan: [
                AgentPlanItem(step: "Inspect current state", status: .completed),
                AgentPlanItem(step: "Apply focused change", status: .inProgress, detail: "Keep the diff small."),
                AgentPlanItem(step: "Run validation", status: .pending)
            ]
        )
        let result = ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        let thread = ChatThread(
            title: "Plan work",
            messages: [.init(role: .user, content: "plan the work")],
            events: [
                .init(
                    kind: .toolCompleted,
                    summary: "\(ToolDefinition.planUpdate.name) completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertEqual(activity.planItems.map(\.title), [
            "Inspect current state",
            "Apply focused change",
            "Run validation"
        ])
        XCTAssertEqual(activity.planItems.map(\.statusLabel), ["Done", "Running", "Pending"])
        XCTAssertEqual(activity.planItems[0].detail, "The model is planning the work directly.")
        XCTAssertEqual(activity.planItems[1].detail, "Keep the diff small.")
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.countLabel, "3 items")
        XCTAssertEqual(activity.sections.first { $0.kind == .plan }?.items.map(\.kind), [
            "authored-plan",
            "authored-plan",
            "authored-plan"
        ])
    }

    func testActivitySurfacePrefersModelAuthoredHandoffSummary() throws {
        let update = AgentHandoffUpdate(
            summary: "The branch is ready for final validation.",
            nextSteps: ["Run focused tests", "Open a PR"]
        )
        let result = ToolResult(ok: true, stdout: try JSONHelpers.encodePretty(update))
        let thread = ChatThread(
            title: "Handoff work",
            messages: [.init(role: .user, content: "summarize for handoff")],
            events: [
                .init(
                    kind: .toolCompleted,
                    summary: "\(ToolDefinition.handoffUpdate.name) completed",
                    payloadJSON: try JSONHelpers.encodePretty(result)
                )
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        let activity = model.surface().activity

        XCTAssertEqual(
            activity.handoffSummary,
            """
            The branch is ready for final validation.
            Next steps:
            1. Run focused tests
            2. Open a PR
            """
        )
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.bodyText, activity.handoffSummary)
        XCTAssertEqual(activity.sections.first { $0.kind == .handoff }?.countLabel, "1 summary")
    }

    func testActivityCommandTogglesActivityPane() {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-activity", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertTrue(model.surface().activity.isVisible)
    }

    func testActivitySectionToggleCollapsesSharedSurfaceSection() throws {
        let call = ToolCall(
            id: "tool-activity",
            name: ToolDefinition.shellRun.name,
            argumentsJSON: #"{"cmd":"whoami"}"#
        )
        let result = ToolResult(ok: true, stdout: "quill\n")
        let thread = ChatThread(
            title: "Run command",
            messages: [.init(role: .user, content: "run whoami")],
            events: [
                .init(kind: .toolQueued, summary: "host.shell.run queued", payloadJSON: try JSONHelpers.encodePretty(call)),
                .init(kind: .toolCompleted, summary: "host.shell.run completed", payloadJSON: try JSONHelpers.encodePretty(result))
            ]
        )
        let model = QuillCodeWorkspaceModel(
            root: QuillCodeRootState(threads: [thread], selectedThreadID: thread.id),
            activity: ActivityState(isVisible: true)
        )

        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, false)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:tools", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, true)
        XCTAssertTrue(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:handoff", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .handoff }?.isCollapsed, true)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:plan", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .plan }?.isCollapsed, true)
        XCTAssertTrue(model.runWorkspaceCommand("activity-toggle-section:tools", workspaceRoot: URL(fileURLWithPath: "/tmp")))
        XCTAssertEqual(model.surface().activity.sections.first { $0.kind == .tools }?.isCollapsed, false)
        XCTAssertFalse(model.runWorkspaceCommand("activity-toggle-section:not-real", workspaceRoot: URL(fileURLWithPath: "/tmp")))
    }

    func testPlanUpdateToolRecordsNormalizedActivityPlan() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = AgentPlanUpdate(
            explanation: "  Keep the plan visible while work proceeds.  ",
            plan: [
                AgentPlanItem(step: "  Inspect state  ", status: .completed),
                AgentPlanItem(step: "Implement change", status: .inProgress, detail: "  One reviewable slice.  "),
                AgentPlanItem(step: "Validate and summarize", status: .pending)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(AgentPlanUpdate.self, from: result.stdout)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.explanation, "Keep the plan visible while work proceeds.")
        XCTAssertEqual(decoded.plan.map(\.step), ["Inspect state", "Implement change", "Validate and summarize"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.planUpdate.name) completed")
        XCTAssertEqual(model.surface().activity.planItems.map(\.title), [
            "Inspect state",
            "Implement change",
            "Validate and summarize"
        ])
        XCTAssertEqual(model.surface().activity.planItems.map(\.statusLabel), ["Done", "Running", "Pending"])
        XCTAssertEqual(model.surface().activity.planItems[1].detail, "One reviewable slice.")
    }

    func testPlanUpdateToolRejectsMultipleRunningSteps() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let update = AgentPlanUpdate(
            plan: [
                AgentPlanItem(step: "First", status: .inProgress),
                AgentPlanItem(step: "Second", status: .inProgress)
            ]
        )
        let call = ToolCall(
            name: ToolDefinition.planUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Plan update can have at most one in_progress step.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }

    func testHandoffUpdateToolRecordsNormalizedActivitySummary() throws {
        let model = QuillCodeWorkspaceModel(activity: ActivityState(isVisible: true))
        _ = model.newChat()
        let update = AgentHandoffUpdate(
            summary: "  Current state:\n\n  implementation is ready.  ",
            nextSteps: ["  Run tests  ", "Open PR"]
        )
        let call = ToolCall(
            name: ToolDefinition.handoffUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(update)
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())
        let decoded = try JSONHelpers.decode(AgentHandoffUpdate.self, from: result.stdout)

        XCTAssertTrue(result.ok, result.error ?? "")
        XCTAssertEqual(decoded.summary, "Current state:\nimplementation is ready.")
        XCTAssertEqual(decoded.nextSteps, ["Run tests", "Open PR"])
        XCTAssertEqual(model.selectedThread?.events.last?.summary, "\(ToolDefinition.handoffUpdate.name) completed")
        XCTAssertTrue(model.surface().activity.handoffSummary?.contains("Current state") == true)
        XCTAssertTrue(model.surface().activity.handoffSummary?.contains("1. Run tests") == true)
    }

    func testHandoffUpdateToolRejectsEmptySummary() throws {
        let model = QuillCodeWorkspaceModel()
        _ = model.newChat()
        let call = ToolCall(
            name: ToolDefinition.handoffUpdate.name,
            argumentsJSON: try JSONHelpers.encodePretty(AgentHandoffUpdate(summary: "  "))
        )

        let result = model.runToolCall(call, workspaceRoot: try makeTempDirectory())

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.error, "Handoff update requires a non-empty summary.")
        XCTAssertEqual(model.root.topBar.agentStatus, "Failed")
    }
}
