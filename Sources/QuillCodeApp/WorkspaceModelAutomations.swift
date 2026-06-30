import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func setAutomations(_ items: [QuillAutomation]) {
        applyAutomationState(WorkspaceAutomationStateReducer.setItems(
            items,
            isVisible: automations.isVisible
        ))
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        scheduleDescription: String = "Manual follow-up",
        nextRunAt: Date? = nil,
        recurrence: QuillAutomationRecurrence? = nil,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let thread = selectedThread else { return nil }
        let mutation = WorkspaceAutomationStateReducer.createThreadFollowUp(
            in: automations,
            thread: thread,
            selectedProjectID: root.selectedProjectID,
            scheduleDescription: scheduleDescription,
            nextRunAt: nextRunAt,
            recurrence: recurrence,
            now: now
        )
        applyAutomationState(mutation.state)
        return mutation.value
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        after seconds: TimeInterval,
        now: Date = Date()
    ) -> QuillAutomation? {
        guard let schedule = WorkspaceAutomationFactory.relativeSchedule(seconds: seconds, now: now) else {
            return nil
        }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.description,
            nextRunAt: schedule.nextRunAt,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        matching scheduleText: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        guard let schedule = ThreadFollowUpScheduleParser.parse(
            scheduleText,
            now: now,
            calendar: calendar
        ) else {
            reportUnrecognizedAutomationSchedule(
                "Could not understand that follow-up schedule. Try `/follow-up in 30 minutes`, `/follow-up Friday at 4 PM`, or `/follow-up daily`."
            )
            return nil
        }
        return createThreadFollowUpAutomation(
            scheduleDescription: schedule.scheduleDescription,
            nextRunAt: schedule.nextRunAt,
            recurrence: schedule.recurrence,
            now: now
        )
    }

    @discardableResult
    public func createThreadFollowUpAutomation(
        every recurrence: QuillAutomationRecurrence,
        now: Date = Date()
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: recurrence.scheduleDescription,
            nextRunAt: recurrence.nextRun(after: now),
            recurrence: recurrence,
            now: now
        )
    }

    @discardableResult
    public func createTomorrowMorningThreadFollowUpAutomation(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> QuillAutomation? {
        createThreadFollowUpAutomation(
            scheduleDescription: "Tomorrow at 9:00 AM",
            nextRunAt: WorkspaceAutomationFactory.tomorrowMorning(from: now, calendar: calendar),
            now: now
        )
    }

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
            reportUnrecognizedAutomationSchedule(
                "Could not understand that workspace-check schedule. Try `/workspace-check in 1 hour`, `/workspace-check Friday morning`, or `/workspace-check every 2 hours`."
            )
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

    private func reportUnrecognizedAutomationSchedule(_ message: String) {
        setLastError(message)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }
}
