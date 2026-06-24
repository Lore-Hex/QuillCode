import Foundation
import XCTest
import QuillCodeCore
import QuillCodePersistence
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
        XCTAssertEqual(workspace.model.surface().automations.workflows.first?.statusLabel, "Ran")
        XCTAssertEqual(workspace.model.surface().automations.statusLabel, "1 active")
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
        let unsupported = QuillAutomation(
            title: "Due monitor",
            detail: "Monitor runner pending.",
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: "Now",
            nextRunAt: Date(timeIntervalSince1970: 70)
        )
        let workspace = try makeAutomationWorkspace(rootState: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id,
            threads: [source],
            selectedThreadID: source.id
        ))
        workspace.model.setAutomations([future, paused, unsupported, due, workspaceDue])

        let followUpIDs = workspace.model.runDueAutomations(now: now)

        XCTAssertEqual(followUpIDs.count, 2)
        let followUp = try XCTUnwrap(workspace.model.root.threads.first { $0.title == "Follow-up: Due follow-up" })
        XCTAssertEqual(followUp.title, "Follow-up: Due follow-up")
        let workspaceCheck = try XCTUnwrap(workspace.model.root.threads.first { $0.title == "Scheduled check: QuillCode" })
        XCTAssertEqual(workspaceCheck.projectID, project.id)
        XCTAssertTrue([followUp.id, workspaceCheck.id].contains(try XCTUnwrap(workspace.model.root.selectedThreadID)))

        let savedAutomations = try workspace.automationStore.load()
        let savedDue = try XCTUnwrap(savedAutomations.first { $0.id == due.id })
        XCTAssertNotNil(savedDue.lastRunAt)
        XCTAssertNil(savedDue.nextRunAt)
        let savedWorkspaceDue = try XCTUnwrap(savedAutomations.first { $0.id == workspaceDue.id })
        XCTAssertNotNil(savedWorkspaceDue.lastRunAt)
        XCTAssertNil(savedWorkspaceDue.nextRunAt)
        XCTAssertEqual(savedAutomations.first { $0.id == future.id }?.nextRunAt, future.nextRunAt)
        XCTAssertEqual(savedAutomations.first { $0.id == paused.id }?.nextRunAt, paused.nextRunAt)
        XCTAssertEqual(savedAutomations.first { $0.id == unsupported.id }?.nextRunAt, unsupported.nextRunAt)
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

    private func makeProjectAutomationWorkspace() throws -> AutomationWorkspace {
        let root = try makeQuillCodeTestDirectory()
        let project = ProjectRef(name: "QuillCode", path: root.path)
        return try makeAutomationWorkspace(root: root, rootState: QuillCodeRootState(
            projects: [project],
            selectedProjectID: project.id
        ))
    }

    private func makeAutomationWorkspace(
        root: URL? = nil,
        rootState: QuillCodeRootState? = nil
    ) throws -> AutomationWorkspace {
        let resolvedRoot: URL
        if let root {
            resolvedRoot = root
        } else {
            resolvedRoot = try makeQuillCodeTestDirectory()
        }
        let paths = QuillCodePaths(home: resolvedRoot.appendingPathComponent(".quillcode"))
        try paths.ensure()
        let automationStore = JSONAutomationStore(fileURL: paths.automationsFile)
        let threadStore = JSONThreadStore(directory: paths.threadsDirectory)
        let model: QuillCodeWorkspaceModel
        if let rootState {
            model = QuillCodeWorkspaceModel(
                root: rootState,
                threadStore: threadStore,
                automationStore: automationStore
            )
        } else {
            model = QuillCodeWorkspaceModel(
                threadStore: threadStore,
                automationStore: automationStore
            )
        }
        return AutomationWorkspace(
            root: resolvedRoot,
            automationStore: automationStore,
            threadStore: threadStore,
            model: model
        )
    }

    private func threadFollowUpAutomation(
        title: String,
        detail: String = "Resume this thread.",
        status: QuillAutomationStatus = .active,
        threadID: UUID,
        scheduleDescription: String = "Now",
        nextRunAt: Date
    ) -> QuillAutomation {
        QuillAutomation(
            title: title,
            detail: detail,
            kind: .threadFollowUp,
            status: status,
            scheduleKind: .heartbeat,
            scheduleDescription: scheduleDescription,
            threadID: threadID,
            nextRunAt: nextRunAt
        )
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeUTCDate(day: Int, hour: Int, minute: Int) -> Date? {
        let calendar = makeUTCCalendar()
        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 1970,
            month: 1,
            day: day,
            hour: hour,
            minute: minute,
            second: 0
        ))
    }
}

private struct AutomationWorkspace {
    var root: URL
    var automationStore: JSONAutomationStore
    var threadStore: JSONThreadStore
    var model: QuillCodeWorkspaceModel
}
