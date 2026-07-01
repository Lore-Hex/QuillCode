import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func createWorkspaceScheduleAutomation(
        scheduleDescription: String = "Manual workspace check",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let project = selectedProject else { return nil }
        let mutation = WorkspaceAutomationStateReducer.createWorkspaceSchedule(
            in: automations,
            project: project,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        applyAutomationState(mutation.state)
        return mutation.value
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        after seconds: TimeInterval,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else {
            return nil
        }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            reportUnrecognizedAutomationSchedule(workspaceScheduleErrorMessage)
            return nil
        }
        return createWorkspaceScheduleAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createWorkspaceScheduleAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningWorkspaceScheduleAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createWorkspaceScheduleAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }
}

private let workspaceScheduleErrorMessage = """
Could not understand that workspace-check schedule. Try `/workspace-check in 1 hour`, \
`/workspace-check Friday morning`, or `/workspace-check every 2 hours`.
"""
