import XCTest
import QuillCodeCore
@testable import QuillCodeApp

final class WorkspaceAutomationEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testThreadFollowUpFactoryUsesFallbackTitleAndSelectedProject() {
        let selectedProjectID = UUID()
        let thread = ChatThread(title: "   ")

        let automation = WorkspaceAutomationFactory.threadFollowUp(
            for: thread,
            selectedProjectID: selectedProjectID,
            scheduleDescription: "Manual follow-up",
            nextRunAt: nil,
            recurrence: nil,
            now: now
        )

        XCTAssertEqual(automation.title, "Thread follow-up")
        XCTAssertEqual(automation.detail, "Resume this thread with the same project, model, and context.")
        XCTAssertEqual(automation.kind, .threadFollowUp)
        XCTAssertEqual(automation.scheduleKind, .heartbeat)
        XCTAssertEqual(automation.scheduleDescription, "Manual follow-up")
        XCTAssertEqual(automation.projectID, selectedProjectID)
        XCTAssertEqual(automation.threadID, thread.id)
        XCTAssertEqual(automation.createdAt, now)
        XCTAssertEqual(automation.updatedAt, now)
        XCTAssertNil(automation.nextRunAt)
        XCTAssertNil(automation.recurrence)
    }

    func testThreadFollowUpFactoryKeepsThreadProjectWhenAvailable() {
        let threadProjectID = UUID()
        let selectedProjectID = UUID()
        let thread = ChatThread(title: "Launch Plan", projectID: threadProjectID)

        let automation = WorkspaceAutomationFactory.threadFollowUp(
            for: thread,
            selectedProjectID: selectedProjectID,
            scheduleDescription: "In 10 minutes",
            nextRunAt: now.addingTimeInterval(600),
            recurrence: nil,
            now: now
        )

        XCTAssertEqual(automation.title, "Follow up: Launch Plan")
        XCTAssertEqual(automation.projectID, threadProjectID)
        XCTAssertEqual(automation.nextRunAt, now.addingTimeInterval(600))
    }

    func testWorkspaceScheduleFactoryBuildsCronAutomation() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let recurrence = QuillAutomationRecurrence(interval: 2, unit: .hours)

        let automation = WorkspaceAutomationFactory.workspaceSchedule(
            for: project,
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )

        XCTAssertEqual(automation.title, "Workspace check: QuillCode")
        XCTAssertEqual(automation.detail, "Create a scheduled workspace-check thread for QuillCode.")
        XCTAssertEqual(automation.kind, .workspaceSchedule)
        XCTAssertEqual(automation.scheduleKind, .cron)
        XCTAssertEqual(automation.projectID, project.id)
        XCTAssertNil(automation.threadID)
        XCTAssertEqual(automation.recurrence, recurrence)
        XCTAssertEqual(automation.nextRunAt, now.addingTimeInterval(2 * 60 * 60))
    }

    func testRelativeScheduleRejectsNonPositiveDurations() {
        XCTAssertNil(WorkspaceAutomationFactory.relativeSchedule(seconds: 0, now: now))
        XCTAssertNil(WorkspaceAutomationFactory.relativeSchedule(seconds: -1, now: now))
    }

    func testRelativeScheduleBuildsDescriptionAndNextRun() throws {
        let schedule = try XCTUnwrap(WorkspaceAutomationFactory.relativeSchedule(seconds: 45 * 60, now: now))

        XCTAssertEqual(schedule.description, "In 45 minutes")
        XCTAssertEqual(schedule.nextRunAt, now.addingTimeInterval(45 * 60))
    }

    func testTomorrowMorningUsesCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fridayNight = Date(timeIntervalSince1970: 1_000)

        let tomorrow = WorkspaceAutomationFactory.tomorrowMorning(from: fridayNight, calendar: calendar)

        XCTAssertEqual(
            tomorrow,
            calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 1970,
                month: 1,
                day: 2,
                hour: 9,
                minute: 0,
                second: 0
            ))
        )
    }

    func testDueAutomationIDsFiltersRunnableDueItemsAndHonorsLimit() {
        let sourceID = UUID()
        let firstDue = automation(
            title: "First",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            threadID: sourceID,
            nextRunAt: now.addingTimeInterval(-20)
        )
        let secondDue = automation(
            title: "Second",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            projectID: UUID(),
            nextRunAt: now.addingTimeInterval(-10)
        )
        let future = automation(
            title: "Future",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            threadID: sourceID,
            nextRunAt: now.addingTimeInterval(10)
        )
        let paused = automation(
            title: "Paused",
            kind: .threadFollowUp,
            status: .paused,
            scheduleKind: .heartbeat,
            threadID: sourceID,
            nextRunAt: now.addingTimeInterval(-30)
        )
        let monitor = automation(
            title: "Monitor",
            kind: .monitor,
            scheduleKind: .event,
            nextRunAt: now.addingTimeInterval(-40)
        )

        let ids = WorkspaceAutomationRunner.dueAutomationIDs(
            in: [future, paused, monitor, firstDue, secondDue],
            now: now,
            limit: 1
        )

        XCTAssertEqual(ids, [firstDue.id])
    }

    func testUpdatedAfterRunAdvancesRecurringAutomation() {
        let recurrence = QuillAutomationRecurrence(interval: 3, unit: .hours)
        let recurring = automation(
            title: "Recurring",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            projectID: UUID(),
            nextRunAt: now.addingTimeInterval(-10),
            recurrence: recurrence
        )

        let updated = WorkspaceAutomationRunner.updatedAfterRun(recurring, now: now)

        XCTAssertEqual(updated.lastRunAt, now)
        XCTAssertEqual(updated.updatedAt, now)
        XCTAssertEqual(updated.nextRunAt, now.addingTimeInterval(3 * 60 * 60))
    }

    func testUpdatedAfterRunClearsOneShotAutomationNextRun() {
        let oneShot = automation(
            title: "One shot",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            threadID: UUID(),
            nextRunAt: now.addingTimeInterval(-10)
        )

        let updated = WorkspaceAutomationRunner.updatedAfterRun(oneShot, now: now)

        XCTAssertEqual(updated.lastRunAt, now)
        XCTAssertNil(updated.nextRunAt)
    }

    func testThreadFollowUpDraftCreatesCopiedThreadAndReport() {
        let source = ChatThread(
            title: "Launch plan",
            projectID: UUID(),
            mode: .review,
            model: "trustedrouter/fusion",
            messages: [
                .init(role: .user, content: "Latest question"),
                .init(role: .assistant, content: "Latest answer")
            ],
            instructions: [
                ProjectInstruction(path: "AGENTS.md", title: "AGENTS.md", content: "Use tests.", byteCount: 10)
            ],
            memories: [
                MemoryNote(
                    id: "project:notes",
                    scope: .project,
                    title: "Notes",
                    content: "Remember release goals.",
                    relativePath: ".quillcode/memories/notes.md",
                    byteCount: 23
                )
            ]
        )
        let projectID = UUID()
        let automation = automation(
            title: "Follow up: Launch plan",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            threadID: source.id,
            nextRunAt: now.addingTimeInterval(-10)
        )

        let draft = WorkspaceAutomationRunner.threadFollowUpDraft(
            automation: automation,
            source: source,
            selectedProjectID: projectID,
            copiedMessages: source.messages,
            now: now
        )

        XCTAssertEqual(draft.automation.lastRunAt, now)
        XCTAssertNil(draft.automation.nextRunAt)
        XCTAssertEqual(draft.thread.title, "Follow-up: Launch plan")
        XCTAssertEqual(draft.thread.projectID, projectID)
        XCTAssertEqual(draft.thread.mode, .review)
        XCTAssertEqual(draft.thread.model, "trustedrouter/fusion")
        XCTAssertEqual(draft.thread.messages, source.messages)
        XCTAssertEqual(draft.thread.events.map(\.summary), [
            "Automation ran: Follow up: Launch plan",
            "Followed up from Launch plan"
        ])
        XCTAssertEqual(draft.thread.instructions, source.instructions)
        XCTAssertEqual(draft.thread.memories, source.memories)
        XCTAssertEqual(draft.selectedProjectID, projectID)
        XCTAssertEqual(draft.report.automationID, automation.id)
        XCTAssertEqual(draft.report.followUpThreadID, draft.thread.id)
        XCTAssertEqual(draft.report.title, "QuillCode follow-up ready")
        XCTAssertEqual(draft.report.body, "Follow-up: Launch plan was created from Launch plan.")
    }

    func testWorkspaceScheduleDraftCreatesProjectThreadAndReport() {
        let project = ProjectRef(name: "QuillCode", path: "/tmp/QuillCode")
        let instructions = [
            ProjectInstruction(path: "AGENTS.md", title: "AGENTS.md", content: "Use tests.", byteCount: 10)
        ]
        let memories = [
            MemoryNote(
                id: "project:notes",
                scope: .project,
                title: "Notes",
                content: "Remember release goals.",
                relativePath: ".quillcode/memories/notes.md",
                byteCount: 23
            )
        ]
        let automation = automation(
            title: "Workspace check: QuillCode",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            projectID: project.id,
            nextRunAt: now.addingTimeInterval(-10)
        )

        let draft = WorkspaceAutomationRunner.workspaceScheduleDraft(
            automation: automation,
            project: project,
            mode: .auto,
            model: "trustedrouter/fast",
            instructions: instructions,
            memories: memories,
            now: now
        )

        XCTAssertEqual(draft.automation.lastRunAt, now)
        XCTAssertNil(draft.automation.nextRunAt)
        XCTAssertEqual(draft.thread.title, "Scheduled check: QuillCode")
        XCTAssertEqual(draft.thread.projectID, project.id)
        XCTAssertEqual(draft.thread.mode, .auto)
        XCTAssertEqual(draft.thread.model, "trustedrouter/fast")
        XCTAssertEqual(draft.thread.messages.map(\.content), [
            "Run the scheduled workspace check for QuillCode. Start with project status, recent changes, local actions, and anything needing attention."
        ])
        XCTAssertEqual(draft.thread.events.first?.summary, "Automation ran: Workspace check: QuillCode")
        XCTAssertEqual(draft.thread.events.first?.payloadJSON, automation.id.uuidString)
        XCTAssertEqual(draft.thread.instructions, instructions)
        XCTAssertEqual(draft.thread.memories, memories)
        XCTAssertEqual(draft.selectedProjectID, project.id)
        XCTAssertEqual(draft.report.automationID, automation.id)
        XCTAssertEqual(draft.report.followUpThreadID, draft.thread.id)
        XCTAssertEqual(draft.report.title, "QuillCode workspace check ready")
        XCTAssertEqual(draft.report.body, "Scheduled check: QuillCode was created for QuillCode.")
    }

    private func automation(
        title: String,
        kind: QuillAutomationKind,
        status: QuillAutomationStatus = .active,
        scheduleKind: QuillAutomationScheduleKind,
        projectID: UUID? = nil,
        threadID: UUID? = nil,
        nextRunAt: Date?,
        recurrence: QuillAutomationRecurrence? = nil
    ) -> QuillAutomation {
        QuillAutomation(
            title: title,
            detail: "Test automation.",
            kind: kind,
            status: status,
            scheduleKind: scheduleKind,
            scheduleDescription: "Now",
            projectID: projectID,
            threadID: threadID,
            createdAt: now,
            updatedAt: now,
            nextRunAt: nextRunAt,
            recurrence: recurrence
        )
    }
}
