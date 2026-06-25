import Foundation
import XCTest
import QuillCodeCore
@testable import QuillCodeApp

@MainActor
final class WorkspaceAutomationSchedulingIntegrationTests: XCTestCase {
    func testScheduledThreadFollowUpsPersistConcreteRunTimes() throws {
        let thread = ChatThread(title: "Launch plan")
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = makeUTCCalendar()

        let tenMinute = try XCTUnwrap(workspace.model.createThreadFollowUpAutomation(after: 600, now: now))
        let tomorrow = try XCTUnwrap(workspace.model.createTomorrowMorningThreadFollowUpAutomation(
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(tenMinute.scheduleDescription, "In 10 minutes")
        XCTAssertEqual(tenMinute.nextRunAt, now.addingTimeInterval(600))
        XCTAssertEqual(tomorrow.scheduleDescription, "Tomorrow at 9:00 AM")
        XCTAssertEqual(tomorrow.nextRunAt, makeUTCDate(day: 2, hour: 9, minute: 0))

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.map(\.scheduleDescription), ["In 10 minutes", "Tomorrow at 9:00 AM"])
        XCTAssertEqual(saved.map(\.threadID), [thread.id, thread.id])
    }

    func testNaturalLanguageScheduledThreadFollowUpsPersistConcreteRunTimes() throws {
        let thread = ChatThread(title: "Launch plan")
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = makeUTCCalendar()

        let relative = try XCTUnwrap(workspace.model.createThreadFollowUpAutomation(
            matching: "in 45 minutes",
            now: now,
            calendar: calendar
        ))
        let tomorrow = try XCTUnwrap(workspace.model.createThreadFollowUpAutomation(
            matching: "tomorrow at 9:30 PM",
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(relative.scheduleDescription, "In 45 minutes")
        XCTAssertEqual(relative.nextRunAt, now.addingTimeInterval(45 * 60))
        XCTAssertEqual(tomorrow.scheduleDescription, "Tomorrow at 9:30 PM")
        XCTAssertEqual(tomorrow.nextRunAt, makeUTCDate(day: 2, hour: 21, minute: 30))

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.map(\.scheduleDescription), ["In 45 minutes", "Tomorrow at 9:30 PM"])
        XCTAssertEqual(saved.map(\.threadID), [thread.id, thread.id])
    }

    func testScheduledWorkspaceChecksPersistConcreteRunTimes() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = makeUTCCalendar()

        let tenMinute = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(after: 600, now: now))
        let tomorrow = try XCTUnwrap(workspace.model.createTomorrowMorningWorkspaceScheduleAutomation(
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(tenMinute.title, "Workspace check: QuillCode")
        XCTAssertEqual(tenMinute.scheduleDescription, "In 10 minutes")
        XCTAssertEqual(tenMinute.nextRunAt, now.addingTimeInterval(600))
        XCTAssertEqual(tomorrow.scheduleDescription, "Tomorrow at 9:00 AM")
        XCTAssertEqual(tomorrow.nextRunAt, makeUTCDate(day: 2, hour: 9, minute: 0))

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.map(\.kind), [.workspaceSchedule, .workspaceSchedule])
        XCTAssertEqual(saved.map(\.scheduleDescription), ["In 10 minutes", "Tomorrow at 9:00 AM"])
        XCTAssertEqual(saved.map(\.projectID), [project.id, project.id])
        XCTAssertEqual(saved.map(\.threadID), [nil, nil])
    }

    func testNaturalLanguageScheduledWorkspaceChecksPersistConcreteRunTimes() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)
        let now = Date(timeIntervalSince1970: 1_000)
        let calendar = makeUTCCalendar()

        let relative = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "in 2 hours",
            now: now,
            calendar: calendar
        ))
        let tomorrow = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "tomorrow at 8:15 AM",
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(relative.scheduleDescription, "In 2 hours")
        XCTAssertEqual(relative.nextRunAt, now.addingTimeInterval(2 * 60 * 60))
        XCTAssertEqual(tomorrow.scheduleDescription, "Tomorrow at 8:15 AM")
        XCTAssertEqual(tomorrow.nextRunAt, makeUTCDate(day: 2, hour: 8, minute: 15))

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.map(\.kind), [.workspaceSchedule, .workspaceSchedule])
        XCTAssertEqual(saved.map(\.scheduleDescription), ["In 2 hours", "Tomorrow at 8:15 AM"])
        XCTAssertEqual(saved.map(\.projectID), [project.id, project.id])
    }

    func testNaturalLanguageRecurringWorkspaceChecksPersistRecurrence() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let now = Date(timeIntervalSince1970: 1_000)

        let recurring = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "every 2 hours",
            now: now
        ))

        XCTAssertEqual(recurring.scheduleDescription, "Every 2 hours")
        XCTAssertEqual(recurring.recurrence, QuillAutomationRecurrence(interval: 2, unit: .hours))
        XCTAssertEqual(recurring.nextRunAt, now.addingTimeInterval(2 * 60 * 60))

        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(saved.scheduleDescription, "Every 2 hours")
        XCTAssertEqual(saved.recurrence, QuillAutomationRecurrence(interval: 2, unit: .hours))
        XCTAssertEqual(saved.nextRunAt, now.addingTimeInterval(2 * 60 * 60))
    }

    func testSlashFollowUpSchedulesCurrentThread() async throws {
        let thread = ChatThread(title: "Launch plan")
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        workspace.model.setDraft("/follow-up in 45 minutes")
        await workspace.model.submitComposer(workspaceRoot: workspace.root)

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.title, "Follow up: Launch plan")
        XCTAssertEqual(saved.first?.scheduleDescription, "In 45 minutes")
        XCTAssertNotNil(saved.first?.nextRunAt)
        XCTAssertEqual(workspace.model.selectedThread?.messages.last?.content, "Scheduled a thread follow-up for In 45 minutes.")
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")
    }

    func testSlashWorkspaceCheckSchedulesSelectedProject() async throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)

        workspace.model.setDraft("/workspace-check tomorrow at 8:15 AM")
        await workspace.model.submitComposer(workspaceRoot: workspace.root)

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.title, "Workspace check: QuillCode")
        XCTAssertEqual(saved.first?.projectID, project.id)
        XCTAssertEqual(saved.first?.kind, .workspaceSchedule)
        XCTAssertEqual(saved.first?.scheduleDescription, "Tomorrow at 8:15 AM")
        XCTAssertNotNil(saved.first?.nextRunAt)
        XCTAssertEqual(workspace.model.selectedThread?.messages.last?.content, "Scheduled a workspace check for Tomorrow at 8:15 AM.")
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")
    }

    func testSlashWorkspaceCheckSchedulesRecurringProjectAutomation() async throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)

        workspace.model.setDraft("/workspace-check daily")
        await workspace.model.submitComposer(workspaceRoot: workspace.root)

        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(saved.title, "Workspace check: QuillCode")
        XCTAssertEqual(saved.projectID, project.id)
        XCTAssertEqual(saved.kind, .workspaceSchedule)
        XCTAssertEqual(saved.scheduleDescription, "Every day")
        XCTAssertEqual(saved.recurrence, QuillAutomationRecurrence(interval: 1, unit: .days))
        XCTAssertNotNil(saved.nextRunAt)
        XCTAssertEqual(workspace.model.selectedThread?.messages.last?.content, "Scheduled a workspace check for Every day.")
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")
    }
}
