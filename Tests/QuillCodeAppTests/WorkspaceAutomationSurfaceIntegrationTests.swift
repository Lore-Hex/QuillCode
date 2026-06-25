import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceAutomationSurfaceIntegrationTests: XCTestCase {
    func testAutomationsCommandTogglesAutomationsPaneWithoutActivity() {
        let model = QuillCodeWorkspaceModel()

        XCTAssertFalse(model.surface().automations.isVisible)
        XCTAssertFalse(model.surface().activity.isVisible)
        XCTAssertTrue(model.runWorkspaceCommand("toggle-automations", workspaceRoot: URL(fileURLWithPath: "/tmp")))

        let surface = model.surface()
        XCTAssertTrue(surface.automations.isVisible)
        XCTAssertFalse(surface.activity.isVisible)
        XCTAssertEqual(surface.automations.title, "Automations")
        XCTAssertEqual(surface.automations.workflows.map(\.title), [
            "Thread follow-ups",
            "Workspace schedules",
            "Monitors"
        ])
    }

    func testAutomationsSurfaceUsesConfiguredAutomationRowsWhenPresent() {
        let model = QuillCodeWorkspaceModel(automations: AutomationsState(items: [
            QuillAutomation(
                title: "Nightly repo check",
                detail: "Run tests and summarize failures.",
                kind: .workspaceSchedule,
                scheduleKind: .cron,
                scheduleDescription: "Every weekday at 6:00 PM"
            ),
            QuillAutomation(
                title: "Paused PR monitor",
                detail: "Watch the launch PR after review starts.",
                kind: .monitor,
                status: .paused,
                scheduleKind: .event,
                scheduleDescription: "PR events"
            )
        ]))

        let automations = model.surface().automations

        XCTAssertEqual(automations.statusLabel, "1 active · 1 paused")
        XCTAssertEqual(automations.workflows.map(\.title), ["Nightly repo check", "Paused PR monitor"])
        XCTAssertEqual(automations.workflows.map(\.statusLabel), ["Active", "Paused"])
        XCTAssertEqual(automations.workflows.first?.scheduleLabel, "Every weekday at 6:00 PM")
        XCTAssertEqual(automations.workflows.first?.runActionTitle, "Run now")
        XCTAssertTrue(automations.workflows.first?.runCommandID?.hasPrefix("automation-run:") == true)
        XCTAssertEqual(automations.workflows.first?.primaryActionTitle, "Pause")
        XCTAssertTrue(automations.workflows.first?.primaryCommandID?.hasPrefix("automation-pause:") == true)
        XCTAssertTrue(automations.workflows.first?.deleteCommandID?.hasPrefix("automation-delete:") == true)
        XCTAssertEqual(automations.workflows.last?.primaryActionTitle, "Resume")
        XCTAssertTrue(automations.workflows.last?.primaryCommandID?.hasPrefix("automation-resume:") == true)
    }

    func testThreadFollowUpAutomationsExposeRunNowAction() {
        let model = QuillCodeWorkspaceModel(automations: AutomationsState(items: [
            QuillAutomation(
                title: "Launch follow-up",
                detail: "Resume the launch thread.",
                kind: .threadFollowUp,
                scheduleKind: .heartbeat,
                scheduleDescription: "Manual follow-up",
                threadID: UUID()
            ),
            QuillAutomation(
                title: "Paused follow-up",
                detail: "Resume later.",
                kind: .threadFollowUp,
                status: .paused,
                scheduleKind: .heartbeat,
                scheduleDescription: "Manual follow-up",
                threadID: UUID()
            )
        ]))

        let automations = model.surface().automations

        XCTAssertEqual(automations.workflows.first?.runActionTitle, "Run now")
        XCTAssertTrue(automations.workflows.first?.runCommandID?.hasPrefix("automation-run:") == true)
        XCTAssertNil(automations.workflows.last?.runActionTitle)
        XCTAssertNil(automations.workflows.last?.runCommandID)
    }

    func testAutomationsSurfaceExposesCreateCommandsForSelectedThreadAndProject() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let thread = ChatThread(title: "Ship QuillCode", projectID: project.id)
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [thread],
            selectedThreadID: thread.id
        ))

        let automations = model.surface().automations

        XCTAssertEqual(automations.createThreadFollowUpCommand?.id, "automation-create-thread-follow-up")
        XCTAssertEqual(automations.createThreadFollowUpCommand?.category, WorkspaceCommandPalette.automationsCategory)
        XCTAssertEqual(automations.createThreadFollowUpCommand?.isEnabled, true)
        XCTAssertEqual(automations.scheduleThreadFollowUpCommands.map(\.id), [
            "automation-create-thread-follow-up-after:600",
            "automation-create-thread-follow-up-after:3600",
            "automation-create-thread-follow-up-tomorrow",
            "automation-create-thread-follow-up-every:daily"
        ])
        XCTAssertEqual(automations.scheduleThreadFollowUpCommands.map(\.isEnabled), [true, true, true, true])
        XCTAssertEqual(model.surface().commands.first { $0.id == "automation-create-thread-follow-up" }?.isEnabled, true)
        XCTAssertEqual(
            model.surface().commands
                .filter { $0.id.hasPrefix("automation-create-thread-follow-up-after:") }
                .map(\.isEnabled),
            [true, true]
        )
        XCTAssertEqual(automations.createWorkspaceScheduleCommand?.id, "automation-create-workspace-schedule")
        XCTAssertEqual(automations.createWorkspaceScheduleCommand?.category, WorkspaceCommandPalette.automationsCategory)
        XCTAssertEqual(automations.createWorkspaceScheduleCommand?.isEnabled, true)
        XCTAssertEqual(automations.scheduleWorkspaceScheduleCommands.map(\.id), [
            "automation-create-workspace-schedule-after:600",
            "automation-create-workspace-schedule-after:3600",
            "automation-create-workspace-schedule-tomorrow",
            "automation-create-workspace-schedule-every:daily"
        ])
        XCTAssertEqual(automations.scheduleWorkspaceScheduleCommands.map(\.isEnabled), [true, true, true, true])
        XCTAssertEqual(model.surface().commands.first { $0.id == "automation-create-workspace-schedule" }?.isEnabled, true)
        XCTAssertEqual(
            model.surface().commands
                .filter { $0.id.hasPrefix("automation-create-workspace-schedule-after:") }
                .map(\.isEnabled),
            [true, true]
        )
        XCTAssertEqual(model.surface().commands.first { $0.id == "automation-create-workspace-schedule-tomorrow" }?.isEnabled, true)
    }
}
