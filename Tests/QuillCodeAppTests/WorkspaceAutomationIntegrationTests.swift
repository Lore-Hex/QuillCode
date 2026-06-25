import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceAutomationIntegrationTests: XCTestCase {
    func testModelPersistsAutomationChanges() throws {
        let workspace = try makeAutomationWorkspace()

        workspace.model.setAutomations([
            QuillAutomation(
                title: "Morning check",
                detail: "Summarize the repo state.",
                kind: .workspaceSchedule,
                scheduleKind: .cron,
                scheduleDescription: "Every morning"
            )
        ])

        XCTAssertEqual(try workspace.automationStore.load().map(\.title), ["Morning check"])
    }

    func testAutomationCommandsCreatePauseResumeAndDeletePersistedFollowUp() throws {
        let thread = ChatThread(title: "Launch plan")
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        XCTAssertTrue(workspace.model.runWorkspaceCommand("automation-create-thread-follow-up", workspaceRoot: workspace.root))

        let created = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(created.title, "Follow up: Launch plan")
        XCTAssertEqual(created.threadID, thread.id)
        XCTAssertEqual(created.status, .active)
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")

        XCTAssertTrue(workspace.model.runWorkspaceCommand("automation-pause:\(created.id.uuidString)", workspaceRoot: workspace.root))
        XCTAssertEqual(try workspace.automationStore.load().first?.status, .paused)
        XCTAssertEqual(workspace.model.surface().automations.workflows.first?.primaryActionTitle, "Resume")

        XCTAssertTrue(workspace.model.runWorkspaceCommand("automation-resume:\(created.id.uuidString)", workspaceRoot: workspace.root))
        XCTAssertEqual(try workspace.automationStore.load().first?.status, .active)
        XCTAssertEqual(workspace.model.surface().automations.workflows.first?.primaryActionTitle, "Pause")

        XCTAssertTrue(workspace.model.runWorkspaceCommand("automation-delete:\(created.id.uuidString)", workspaceRoot: workspace.root))
        XCTAssertEqual(try workspace.automationStore.load(), [])
        XCTAssertEqual(workspace.model.surface().automations.workflows.map(\.title), [
            "Thread follow-ups",
            "Workspace schedules",
            "Monitors"
        ])
    }

    func testCreateWorkspaceScheduleCommandPersistsSelectedProjectAutomation() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)

        XCTAssertTrue(workspace.model.runWorkspaceCommand("automation-create-workspace-schedule", workspaceRoot: workspace.root))

        let automation = try XCTUnwrap(workspace.model.automations.items.first)
        XCTAssertEqual(automation.title, "Workspace check: QuillCode")
        XCTAssertEqual(automation.detail, "Create a scheduled workspace-check thread for QuillCode.")
        XCTAssertEqual(automation.kind, .workspaceSchedule)
        XCTAssertEqual(automation.scheduleKind, .cron)
        XCTAssertEqual(automation.scheduleDescription, "Manual workspace check")
        XCTAssertEqual(automation.projectID, project.id)
        XCTAssertNil(automation.threadID)
        XCTAssertNil(automation.nextRunAt)
        XCTAssertTrue(workspace.model.surface().automations.isVisible)

        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(saved.id, automation.id)
        XCTAssertEqual(saved.projectID, project.id)
        XCTAssertEqual(saved.kind, .workspaceSchedule)
    }
}
