import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceAutomationRunIntegrationTests: XCTestCase {
    func testAutomationRunCreatesFollowUpThreadAndPersistsRunMetadata() throws {
        let source = ChatThread(title: "Launch plan", messages: [
            .init(role: .user, content: "latest question"),
            .init(role: .tool, content: #"{"internal":"skip"}"#),
            .init(role: .assistant, content: "latest answer")
        ])
        let automation = QuillAutomation(
            title: "Follow up: Launch plan",
            detail: "Resume this thread with the same project, model, and context.",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            scheduleDescription: "Manual follow-up",
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 1)
        )
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))
        workspace.model.setAutomations([automation])
        workspace.model.startSidebarSelection(selecting: source.id)
        XCTAssertEqual(workspace.model.selectedSidebarThreadIDs(), [source.id])

        XCTAssertTrue(workspace.model.runWorkspaceCommand("automation-run:\(automation.id.uuidString)", workspaceRoot: workspace.root))

        let followUpID = try XCTUnwrap(workspace.model.root.selectedThreadID)
        XCTAssertNotEqual(followUpID, source.id)
        let followUp = try XCTUnwrap(workspace.model.root.threads.first { $0.id == followUpID })
        XCTAssertEqual(followUp.title, "Follow-up: Launch plan")
        XCTAssertEqual(followUp.messages.map(\.content), ["latest question", "latest answer"])
        XCTAssertFalse(followUp.messages.contains { $0.role == .tool })
        XCTAssertEqual(followUp.events.first?.summary, "Automation ran: Follow up: Launch plan")
        XCTAssertEqual(followUp.events.first?.payloadJSON, automation.id.uuidString)

        let savedThread = try workspace.threadStore.load(followUpID)
        XCTAssertEqual(savedThread.title, "Follow-up: Launch plan")
        let savedAutomation = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertNotNil(savedAutomation.lastRunAt)
        XCTAssertNil(savedAutomation.nextRunAt)
        XCTAssertEqual(workspace.model.selectedSidebarThreadIDs(), [])
        XCTAssertEqual(workspace.model.surface().automations.workflows.first?.statusLabel, "Ran")
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")
    }

    func testRunWorkspaceScheduleCreatesScheduledProjectThread() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)
        let automation = QuillAutomation(
            title: "Workspace check: QuillCode",
            detail: "Create a scheduled workspace-check thread for QuillCode.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: "Manual workspace check",
            projectID: project.id
        )
        workspace.model.setAutomations([automation])

        XCTAssertTrue(workspace.model.runWorkspaceCommand("automation-run:\(automation.id.uuidString)", workspaceRoot: workspace.root))

        let scheduledID: UUID = try XCTUnwrap(workspace.model.root.selectedThreadID)
        let scheduled: ChatThread = try XCTUnwrap(workspace.model.root.threads.first { $0.id == scheduledID })
        XCTAssertEqual(scheduled.title, "Scheduled check: QuillCode")
        XCTAssertEqual(scheduled.projectID, project.id)
        XCTAssertEqual(scheduled.messages.map(\.content), [
            "Run the scheduled workspace check for QuillCode. Start with project status, recent changes, local actions, and anything needing attention."
        ])
        XCTAssertEqual(scheduled.events.first?.summary, "Automation ran: Workspace check: QuillCode")
        XCTAssertEqual(scheduled.events.first?.payloadJSON, automation.id.uuidString)

        let savedThread = try workspace.threadStore.load(scheduledID)
        XCTAssertEqual(savedThread.title, "Scheduled check: QuillCode")
        let savedAutomation = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertNotNil(savedAutomation.lastRunAt)
        XCTAssertNil(savedAutomation.nextRunAt)
        XCTAssertEqual(workspace.model.surface().automations.workflows.first?.statusLabel, "Ran")
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")
    }

    func testRunDueAutomationsRunsActiveDueThreadAndWorkspaceSchedules() throws {
        let now = Date(timeIntervalSince1970: 100)
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let source = ChatThread(title: "Due follow-up", messages: [
            .init(role: .user, content: "summarize tomorrow"),
            .init(role: .assistant, content: "I will follow up.")
        ])
        let due = threadFollowUpAutomation(
            title: "Due follow-up",
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 90)
        )
        let workspaceDue = QuillAutomation(
            title: "Due workspace check",
            detail: "Check workspace.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: "Now",
            projectID: project.id,
            nextRunAt: Date(timeIntervalSince1970: 85)
        )
        let future = threadFollowUpAutomation(
            title: "Future follow-up",
            detail: "Resume later.",
            threadID: source.id,
            scheduleDescription: "Later",
            nextRunAt: Date(timeIntervalSince1970: 120)
        )
        let paused = threadFollowUpAutomation(
            title: "Paused follow-up",
            detail: "Do not run.",
            status: .paused,
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 80)
        )
        let monitor = QuillAutomation(
            title: "Due monitor",
            detail: "Watch CI and PR checks.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "Now",
            projectID: project.id,
            nextRunAt: Date(timeIntervalSince1970: 70)
        )
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))
        workspace.model.setAutomations([future, paused, monitor, due, workspaceDue])

        let followUpIDs = workspace.model.runDueAutomations(now: now)

        XCTAssertEqual(followUpIDs.count, 3)
        let monitorThread = try XCTUnwrap(workspace.model.root.threads.first { $0.title == "Monitor: Due monitor" })
        XCTAssertEqual(monitorThread.projectID, project.id)
        XCTAssertEqual(monitorThread.messages.map(\.content), [
            """
            Run the monitor "Due monitor".
            Watch condition: Watch CI and PR checks.
            Use the QuillCode workspace context.
            Report what changed, whether action is needed, and the next concrete step.
            """
        ])
        let followUp = try XCTUnwrap(workspace.model.root.threads.first { $0.title == "Follow-up: Due follow-up" })
        XCTAssertEqual(followUp.title, "Follow-up: Due follow-up")
        let workspaceCheck = try XCTUnwrap(workspace.model.root.threads.first { $0.title == "Scheduled check: QuillCode" })
        XCTAssertEqual(workspaceCheck.projectID, project.id)
        XCTAssertTrue([monitorThread.id, followUp.id, workspaceCheck.id].contains(try XCTUnwrap(workspace.model.root.selectedThreadID)))

        let savedAutomations = try workspace.automationStore.load()
        let savedMonitor = try XCTUnwrap(savedAutomations.first { $0.id == monitor.id })
        XCTAssertNotNil(savedMonitor.lastRunAt)
        XCTAssertNil(savedMonitor.nextRunAt)
        let savedDue = try XCTUnwrap(savedAutomations.first { $0.id == due.id })
        XCTAssertNotNil(savedDue.lastRunAt)
        XCTAssertNil(savedDue.nextRunAt)
        let savedWorkspaceDue = try XCTUnwrap(savedAutomations.first { $0.id == workspaceDue.id })
        XCTAssertNotNil(savedWorkspaceDue.lastRunAt)
        XCTAssertNil(savedWorkspaceDue.nextRunAt)
        XCTAssertEqual(savedAutomations.first { $0.id == future.id }?.nextRunAt, future.nextRunAt)
        XCTAssertEqual(savedAutomations.first { $0.id == paused.id }?.nextRunAt, paused.nextRunAt)
    }

    func testDueRecurringWorkspaceScheduleRunsAndAdvancesNextRun() throws {
        let runAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 60)
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)
        let recurrence = QuillAutomationRecurrence(interval: 2, unit: .hours)
        let recurring = QuillAutomation(
            title: "Recurring workspace check",
            detail: "Check workspace.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: recurrence.scheduleDescription,
            projectID: project.id,
            nextRunAt: runAt.addingTimeInterval(-10),
            recurrence: recurrence
        )
        workspace.model.setAutomations([recurring])

        let reports = workspace.model.runDueAutomationReports(now: runAt)

        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(workspace.model.root.threads.filter { $0.title == "Scheduled check: QuillCode" }.count, 1)
        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertNotNil(saved.lastRunAt)
        XCTAssertEqual(
            try XCTUnwrap(saved.nextRunAt).timeIntervalSince1970,
            recurrence.nextRun(after: runAt).timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertEqual(saved.recurrence, recurrence)
        XCTAssertEqual(workspace.model.surface().automations.workflows.first?.statusLabel, "Active")

        _ = workspace.model.runDueAutomations(now: runAt.addingTimeInterval(60))

        XCTAssertEqual(workspace.model.root.threads.filter { $0.title == "Scheduled check: QuillCode" }.count, 1)
    }

    func testCalendarRecurringAutomationAdvancesToNextMatchingWallClockRun() throws {
        let calendar = makeUTCCalendar()
        let runAt = try XCTUnwrap(makeUTCDate(day: 6, hour: 18, minute: 0))
        let nextRun = try XCTUnwrap(makeUTCDate(day: 7, hour: 18, minute: 0))
        let recurrence = QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: [2, 3, 4, 5, 6],
            hour: 18,
            minute: 0
        )
        let automation = QuillAutomation(
            title: "Weekday check",
            detail: "Check workspace.",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: runAt,
            recurrence: recurrence
        )

        let updated = WorkspaceAutomationRunner.updatedAfterRun(
            automation,
            now: runAt,
            calendar: calendar
        )

        XCTAssertEqual(updated.lastRunAt, runAt)
        XCTAssertEqual(updated.nextRunAt, nextRun)
    }

    func testRunDueAutomationReportsRunsFileChangeMonitorEventSource() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)
        let logDirectory = workspace.root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let watchedFile = logDirectory.appendingPathComponent("watch.txt")
        try "changed".write(to: watchedFile, atomically: true, encoding: .utf8)
        let modifiedAt = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: watchedFile.path)[.modificationDate] as? Date
        )
        let now = Date(timeIntervalSince1970: floor(modifiedAt.timeIntervalSince1970) + 2)
        let monitor = QuillAutomation(
            title: "Watch logs",
            detail: "Summarize watched file changes.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "File changes",
            projectID: project.id,
            eventSource: QuillAutomationEventSource(kind: .fileChange, path: "logs/watch.txt"),
            lastRunAt: modifiedAt.addingTimeInterval(-1)
        )
        workspace.model.setAutomations([monitor])

        let reports = workspace.model.runDueAutomationReports(now: now)

        XCTAssertEqual(reports.count, 1)
        let thread = try XCTUnwrap(workspace.model.root.threads.first { $0.title == "Monitor: Watch logs" })
        XCTAssertEqual(thread.projectID, project.id)
        XCTAssertEqual(thread.messages.map(\.content), [
            """
            Run the monitor "Watch logs".
            Watch condition: Summarize watched file changes.
            Trigger: watch.txt changed
            Use the QuillCode workspace context.
            Report what changed, whether action is needed, and the next concrete step.
            """
        ])
        XCTAssertTrue(thread.events.contains {
            $0.summary == "Monitor trigger: watch.txt changed" && $0.payloadJSON == "logs/watch.txt"
        })

        let saved = try XCTUnwrap(try workspace.automationStore.load().first { $0.id == monitor.id })
        XCTAssertEqual(
            try XCTUnwrap(saved.lastRunAt).timeIntervalSince1970,
            now.timeIntervalSince1970,
            accuracy: 0.001
        )
        XCTAssertNil(saved.nextRunAt)

        let secondReports = workspace.model.runDueAutomationReports(now: now.addingTimeInterval(1))
        XCTAssertEqual(secondReports, [])
        XCTAssertEqual(workspace.model.root.threads.filter { $0.title == "Monitor: Watch logs" }.count, 1)
    }

    func testRunDueAutomationReportsDescribeCreatedFollowUps() throws {
        let now = Date(timeIntervalSince1970: 100)
        let source = ChatThread(title: "Due follow-up", messages: [
            .init(role: .user, content: "summarize tomorrow"),
            .init(role: .assistant, content: "I will follow up.")
        ])
        let due = threadFollowUpAutomation(
            title: "Due follow-up",
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 90)
        )
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))
        workspace.model.setAutomations([due])

        let reports = workspace.model.runDueAutomationReports(now: now)

        let report = try XCTUnwrap(reports.first)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(report.automationID, due.id)
        XCTAssertEqual(report.title, "QuillCode follow-up ready")
        XCTAssertEqual(report.body, "Follow-up: Due follow-up was created from Due follow-up.")
        XCTAssertEqual(workspace.model.root.selectedThreadID, report.followUpThreadID)
        XCTAssertEqual(workspace.model.root.threads.first?.id, report.followUpThreadID)
        XCTAssertEqual(workspace.model.root.threads.first?.title, "Follow-up: Due follow-up")

        let savedDue = try XCTUnwrap(try workspace.automationStore.load().first { $0.id == due.id })
        XCTAssertNotNil(savedDue.lastRunAt)
        XCTAssertNil(savedDue.nextRunAt)
    }

    func testRunDueAutomationsHonorsLimit() throws {
        let now = Date(timeIntervalSince1970: 100)
        let source = ChatThread(title: "Launch plan", messages: [
            .init(role: .user, content: "follow up"),
            .init(role: .assistant, content: "Noted.")
        ])
        let first = threadFollowUpAutomation(
            title: "First follow-up",
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 80)
        )
        let second = threadFollowUpAutomation(
            title: "Second follow-up",
            threadID: source.id,
            nextRunAt: Date(timeIntervalSince1970: 90)
        )
        let model = QuillCodeWorkspaceModel(root: QuillCodeRootState(
            threads: [source],
            selectedThreadID: source.id
        ))
        model.setAutomations([second, first])

        let followUpIDs = model.runDueAutomations(now: now, limit: 1)

        XCTAssertEqual(followUpIDs.count, 1)
        XCTAssertEqual(model.automations.items.first { $0.id == first.id }?.lastRunAt != nil, true)
        XCTAssertNil(model.automations.items.first { $0.id == first.id }?.nextRunAt)
        XCTAssertEqual(model.automations.items.first { $0.id == second.id }?.nextRunAt, second.nextRunAt)
    }
}
