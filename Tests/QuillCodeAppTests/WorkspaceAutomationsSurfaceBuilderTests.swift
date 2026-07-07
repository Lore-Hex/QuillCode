import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAutomationsSurfaceBuilderTests: XCTestCase {
    func testSurfaceIncludesPlannedWorkflowsAndDisabledCommandsWithoutContext() {
        let surface = WorkspaceAutomationsSurfaceBuilder(
            isVisible: true,
            automations: [],
            hasSelectedThread: false,
            hasSelectedProject: false
        ).surface()

        XCTAssertTrue(surface.isVisible)
        XCTAssertEqual(surface.title, "Automations")
        XCTAssertEqual(surface.statusLabel, "3 planned")
        XCTAssertEqual(surface.workflows.map(\.title), [
            "Thread follow-ups",
            "Workspace schedules",
            "Monitors"
        ])
        XCTAssertEqual(surface.createThreadFollowUpCommand?.id, "automation-create-thread-follow-up")
        XCTAssertEqual(surface.createThreadFollowUpCommand?.isEnabled, false)
        XCTAssertEqual(surface.scheduleThreadFollowUpCommands.map(\.isEnabled), [false, false, false, false])
        XCTAssertEqual(surface.createWorkspaceScheduleCommand?.id, "automation-create-workspace-schedule")
        XCTAssertEqual(surface.createWorkspaceScheduleCommand?.isEnabled, false)
        XCTAssertEqual(surface.createMonitorCommand?.id, "automation-create-monitor")
        XCTAssertEqual(surface.createMonitorCommand?.isEnabled, true)
        XCTAssertEqual(surface.scheduleWorkspaceScheduleCommands.map(\.isEnabled), [false, false, false, false])
    }

    func testSurfaceEnablesThreadAndWorkspaceCommandsIndependently() {
        let threadOnly = WorkspaceAutomationsSurfaceBuilder(
            isVisible: false,
            automations: [],
            hasSelectedThread: true,
            hasSelectedProject: false
        ).surface()

        XCTAssertEqual(threadOnly.createThreadFollowUpCommand?.isEnabled, true)
        XCTAssertEqual(threadOnly.scheduleThreadFollowUpCommands.map(\.id), [
            "automation-create-thread-follow-up-after:600",
            "automation-create-thread-follow-up-after:3600",
            "automation-create-thread-follow-up-tomorrow",
            "automation-create-thread-follow-up-every:daily"
        ])
        XCTAssertEqual(threadOnly.scheduleThreadFollowUpCommands.map(\.isEnabled), [true, true, true, true])
        XCTAssertEqual(threadOnly.createWorkspaceScheduleCommand?.isEnabled, false)
        XCTAssertEqual(threadOnly.createMonitorCommand?.isEnabled, true)
        XCTAssertEqual(threadOnly.scheduleWorkspaceScheduleCommands.map(\.isEnabled), [false, false, false, false])

        let workspaceOnly = WorkspaceAutomationsSurfaceBuilder(
            isVisible: false,
            automations: [],
            hasSelectedThread: false,
            hasSelectedProject: true
        ).surface()

        XCTAssertEqual(workspaceOnly.createThreadFollowUpCommand?.isEnabled, false)
        XCTAssertEqual(workspaceOnly.createMonitorCommand?.isEnabled, true)
        XCTAssertEqual(workspaceOnly.scheduleThreadFollowUpCommands.map(\.isEnabled), [false, false, false, false])
        XCTAssertEqual(workspaceOnly.createWorkspaceScheduleCommand?.isEnabled, true)
        XCTAssertEqual(workspaceOnly.scheduleWorkspaceScheduleCommands.map(\.id), [
            "automation-create-workspace-schedule-after:600",
            "automation-create-workspace-schedule-after:3600",
            "automation-create-workspace-schedule-tomorrow",
            "automation-create-workspace-schedule-every:daily"
        ])
        XCTAssertEqual(workspaceOnly.scheduleWorkspaceScheduleCommands.map(\.isEnabled), [true, true, true, true])
    }

    func testSurfaceKeepsConfiguredAutomationActions() {
        let active = QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            title: "Nightly repo check",
            detail: "Run tests and summarize failures.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: "Every weekday at 6:00 PM"
        )
        let paused = QuillAutomation(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            title: "Paused PR monitor",
            detail: "Watch the launch PR after review starts.",
            kind: .monitor,
            status: .paused,
            scheduleKind: .event,
            scheduleDescription: "PR events"
        )

        let surface = WorkspaceAutomationsSurfaceBuilder(
            isVisible: true,
            automations: [active, paused],
            hasSelectedThread: true,
            hasSelectedProject: true
        ).surface()

        XCTAssertEqual(surface.statusLabel, "1 active · 1 paused")
        XCTAssertEqual(surface.workflows.map(\.title), ["Nightly repo check", "Paused PR monitor"])
        XCTAssertEqual(surface.workflows.first?.runActionTitle, "Run now")
        XCTAssertEqual(surface.workflows.first?.runCommandID, "automation-run:00000000-0000-0000-0000-000000000201")
        XCTAssertEqual(surface.workflows.first?.primaryActionTitle, "Pause")
        XCTAssertEqual(surface.workflows.first?.primaryCommandID, "automation-pause:00000000-0000-0000-0000-000000000201")
        XCTAssertEqual(surface.workflows.first?.deleteCommandID, "automation-delete:00000000-0000-0000-0000-000000000201")
        XCTAssertNil(surface.workflows.last?.runActionTitle)
        XCTAssertEqual(surface.workflows.last?.primaryActionTitle, "Resume")
        XCTAssertEqual(surface.workflows.last?.primaryCommandID, "automation-resume:00000000-0000-0000-0000-000000000202")
    }
}
