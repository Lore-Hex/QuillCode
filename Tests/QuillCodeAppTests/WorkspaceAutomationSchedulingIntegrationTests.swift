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

    func testNaturalLanguageScheduledThreadFollowUpsAcceptCalendarPhrases() throws {
        let thread = ChatThread(title: "Launch plan")
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let now = try XCTUnwrap(makeUTCDate(day: 5, hour: 10, minute: 0))
        let calendar = makeUTCCalendar()

        let today = try XCTUnwrap(workspace.model.createThreadFollowUpAutomation(
            matching: "today at 4:15 PM",
            now: now,
            calendar: calendar
        ))
        let tonight = try XCTUnwrap(workspace.model.createThreadFollowUpAutomation(
            matching: "tonight at 8",
            now: now,
            calendar: calendar
        ))
        let nextMonday = try XCTUnwrap(workspace.model.createThreadFollowUpAutomation(
            matching: "next monday at 9",
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(today.scheduleDescription, "Today at 4:15 PM")
        XCTAssertEqual(today.nextRunAt, makeUTCDate(day: 5, hour: 16, minute: 15))
        XCTAssertEqual(tonight.scheduleDescription, "Tonight at 8:00 PM")
        XCTAssertEqual(tonight.nextRunAt, makeUTCDate(day: 5, hour: 20, minute: 0))
        XCTAssertEqual(nextMonday.scheduleDescription, "Next Monday at 9:00 AM")
        XCTAssertEqual(nextMonday.nextRunAt, makeUTCDate(day: 12, hour: 9, minute: 0))
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

    func testNaturalLanguageScheduledWorkspaceChecksAcceptWeekdayAndClockPhrases() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)
        let now = try XCTUnwrap(makeUTCDate(day: 1, hour: 10, minute: 0))
        let calendar = makeUTCCalendar()

        let friday = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "friday afternoon",
            now: now,
            calendar: calendar
        ))
        let bareClock = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "at 8:30 AM",
            now: now,
            calendar: calendar
        ))
        let noon = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "next monday at noon",
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(friday.scheduleDescription, "Friday at 1:00 PM")
        XCTAssertEqual(friday.nextRunAt, makeUTCDate(day: 2, hour: 13, minute: 0))
        XCTAssertEqual(bareClock.scheduleDescription, "Tomorrow at 8:30 AM")
        XCTAssertEqual(bareClock.nextRunAt, makeUTCDate(day: 2, hour: 8, minute: 30))
        XCTAssertEqual(noon.scheduleDescription, "Next Monday at 12:00 PM")
        XCTAssertEqual(noon.nextRunAt, makeUTCDate(day: 5, hour: 12, minute: 0))

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.map(\.kind), [.workspaceSchedule, .workspaceSchedule, .workspaceSchedule])
        XCTAssertEqual(saved.map(\.projectID), [project.id, project.id, project.id])
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

    func testNaturalLanguageRecurringWorkspaceChecksAcceptCalendarRecurrence() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)
        let now = try XCTUnwrap(makeUTCDate(day: 6, hour: 10, minute: 0))
        let calendar = makeUTCCalendar()

        let weekdays = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "every weekday at 6 PM",
            now: now,
            calendar: calendar
        ))
        let monday = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "every monday at noon",
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(weekdays.scheduleDescription, "Every weekday at 6:00 PM")
        XCTAssertEqual(weekdays.nextRunAt, makeUTCDate(day: 6, hour: 18, minute: 0))
        XCTAssertEqual(weekdays.recurrence, QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: [2, 3, 4, 5, 6],
            hour: 18,
            minute: 0
        ))
        XCTAssertEqual(monday.scheduleDescription, "Every Monday at 12:00 PM")
        XCTAssertEqual(monday.nextRunAt, makeUTCDate(day: 12, hour: 12, minute: 0))
        XCTAssertEqual(monday.recurrence, QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: [2],
            hour: 12,
            minute: 0
        ))

        let saved = try workspace.automationStore.load()
        XCTAssertEqual(saved.map(\.kind), [.workspaceSchedule, .workspaceSchedule])
        XCTAssertEqual(saved.map(\.projectID), [project.id, project.id])
        XCTAssertEqual(saved.map(\.scheduleDescription), [
            "Every weekday at 6:00 PM",
            "Every Monday at 12:00 PM"
        ])
    }

    func testCalendarRecurrenceRequiresExplicitRecurringLanguageForWeekdays() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let now = try XCTUnwrap(makeUTCDate(day: 1, hour: 10, minute: 0))
        let calendar = makeUTCCalendar()

        let oneOff = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "friday afternoon",
            now: now,
            calendar: calendar
        ))
        let recurring = try XCTUnwrap(workspace.model.createWorkspaceScheduleAutomation(
            matching: "fridays at 1 PM",
            now: now,
            calendar: calendar
        ))

        XCTAssertNil(oneOff.recurrence)
        XCTAssertEqual(oneOff.scheduleDescription, "Friday at 1:00 PM")
        XCTAssertEqual(recurring.scheduleDescription, "Every Friday at 1:00 PM")
        XCTAssertEqual(recurring.recurrence, QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: [6],
            hour: 13,
            minute: 0
        ))
    }

    func testNaturalLanguageRecurringThreadFollowUpsAcceptCalendarRecurrence() throws {
        let thread = ChatThread(title: "Launch plan")
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))
        let now = try XCTUnwrap(makeUTCDate(day: 3, hour: 19, minute: 0))
        let calendar = makeUTCCalendar()

        let recurring = try XCTUnwrap(workspace.model.createThreadFollowUpAutomation(
            matching: "weekends at 10 AM",
            now: now,
            calendar: calendar
        ))

        XCTAssertEqual(recurring.scheduleDescription, "Every weekend at 10:00 AM")
        XCTAssertEqual(recurring.nextRunAt, makeUTCDate(day: 4, hour: 10, minute: 0))
        XCTAssertEqual(recurring.recurrence, QuillAutomationRecurrence(
            interval: 1,
            unit: .weeks,
            weekdays: [1, 7],
            hour: 10,
            minute: 0
        ))
        XCTAssertEqual(try workspace.automationStore.load().first?.threadID, thread.id)
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

    func testMonitorCreationPersistsFeedEventSource() throws {
        let workspace = try makeProjectAutomationWorkspace()
        let project = try XCTUnwrap(workspace.model.selectedProject)

        let automation = try XCTUnwrap(workspace.model.createMonitorAutomation(
            request: WorkspaceMonitorRequest(
                kind: .urlFeedUpdate,
                path: "https://example.com/feed.xml"
            ),
            now: Date(timeIntervalSince1970: 1_000)
        ))

        XCTAssertEqual(automation.title, "Watch feed: example.com/feed.xml")
        XCTAssertEqual(automation.kind, .monitor)
        XCTAssertEqual(automation.scheduleKind, .event)
        XCTAssertEqual(automation.scheduleDescription, "URL feed update")
        XCTAssertEqual(automation.projectID, project.id)
        XCTAssertEqual(automation.eventSource, QuillAutomationEventSource(
            kind: .urlFeedUpdate,
            path: "https://example.com/feed.xml"
        ))

        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(saved, automation)
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")
    }

    func testSlashMonitorCreatesLastModifiedMonitor() async throws {
        let workspace = try makeProjectAutomationWorkspace()

        workspace.model.setDraft("/monitor last-modified https://example.com/releases")
        await workspace.model.submitComposer(workspaceRoot: workspace.root)

        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(saved.title, "Watch URL header: example.com/releases")
        XCTAssertEqual(saved.kind, .monitor)
        XCTAssertEqual(saved.scheduleDescription, "URL Last-Modified")
        XCTAssertEqual(saved.eventSource, QuillAutomationEventSource(
            kind: .urlLastModified,
            path: "https://example.com/releases"
        ))
        XCTAssertEqual(
            workspace.model.selectedThread?.messages.last?.content,
            "Created Watch URL header: example.com/releases using URL Last-Modified: https://example.com/releases."
        )
    }

    func testSlashMonitorCreatesDirectoryMonitor() async throws {
        let workspace = try makeProjectAutomationWorkspace()
        try FileManager.default.createDirectory(
            at: workspace.root.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )

        workspace.model.setDraft("/monitor directory logs")
        await workspace.model.submitComposer(workspaceRoot: workspace.root)

        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(saved.title, "Watch directory: logs")
        XCTAssertEqual(saved.kind, .monitor)
        XCTAssertEqual(saved.scheduleDescription, "Directory change")
        XCTAssertEqual(saved.eventSource, QuillAutomationEventSource(
            kind: .directoryChange,
            path: "logs"
        ))
        XCTAssertEqual(
            workspace.model.selectedThread?.messages.last?.content,
            "Created Watch directory: logs using Directory change: logs."
        )
    }

    func testSlashMonitorRejectsInvalidURL() async throws {
        let workspace = try makeProjectAutomationWorkspace()

        workspace.model.setDraft("/monitor feed example.com/feed.xml")
        await workspace.model.submitComposer(workspaceRoot: workspace.root)

        XCTAssertEqual(try workspace.automationStore.load(), [])
        XCTAssertEqual(
            workspace.model.selectedThread?.messages.last?.content,
            "Could not watch that feed. Use an explicit http:// or https:// RSS or Atom URL."
        )
    }

    func testSlashFollowUpAcceptsWeekdayCalendarPhrase() async throws {
        let thread = ChatThread(title: "Launch plan")
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            threads: [thread],
            selectedThreadID: thread.id
        ))

        workspace.model.setDraft("/follow-up friday afternoon")
        await workspace.model.submitComposer(workspaceRoot: workspace.root)

        let saved = try XCTUnwrap(try workspace.automationStore.load().first)
        XCTAssertEqual(saved.title, "Follow up: Launch plan")
        XCTAssertEqual(saved.scheduleDescription, "Friday at 1:00 PM")
        XCTAssertNotNil(saved.nextRunAt)
        XCTAssertEqual(workspace.model.selectedThread?.messages.last?.content, "Scheduled a thread follow-up for Friday at 1:00 PM.")
    }
}
