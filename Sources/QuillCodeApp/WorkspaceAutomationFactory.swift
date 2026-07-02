import Foundation
import QuillCodeCore

enum WorkspaceAutomationFactory {
    static func threadFollowUp(
        for thread: ChatThread,
        selectedProjectID: UUID?,
        scheduleDescription: String,
        nextRunAt: Date?,
        recurrence: QuillAutomationRecurrence?,
        now: Date
    ) -> QuillAutomation {
        let title = thread.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuillAutomation(
            title: title.isEmpty ? "Thread follow-up" : "Follow up: \(title)",
            detail: "Resume this thread with the same project, model, and context.",
            kind: .threadFollowUp,
            scheduleKind: .heartbeat,
            scheduleDescription: scheduleDescription,
            projectID: thread.projectID ?? selectedProjectID,
            threadID: thread.id,
            createdAt: now,
            updatedAt: now,
            nextRunAt: nextRunAt,
            recurrence: recurrence
        )
    }

    static func workspaceSchedule(
        for project: ProjectRef,
        scheduleDescription: String,
        nextRunAt: Date?,
        recurrence: QuillAutomationRecurrence?,
        now: Date
    ) -> QuillAutomation {
        QuillAutomation(
            title: "Workspace check: \(project.name)",
            detail: "Create a scheduled workspace-check thread for \(project.name).",
            kind: .workspaceSchedule,
            scheduleKind: .cron,
            scheduleDescription: scheduleDescription,
            projectID: project.id,
            createdAt: now,
            updatedAt: now,
            nextRunAt: nextRunAt,
            recurrence: recurrence
        )
    }

    static func localEnvironmentAction(
        for project: ProjectRef,
        action: LocalEnvironmentAction,
        scheduleDescription: String,
        nextRunAt: Date?,
        recurrence: QuillAutomationRecurrence?,
        now: Date
    ) -> QuillAutomation {
        QuillAutomation(
            title: "Local action: \(action.title)",
            detail: "Run \(action.title) in \(project.name).",
            kind: .localEnvironmentAction,
            scheduleKind: .cron,
            scheduleDescription: scheduleDescription,
            projectID: project.id,
            localEnvironmentActionID: action.id,
            createdAt: now,
            updatedAt: now,
            nextRunAt: nextRunAt,
            recurrence: recurrence
        )
    }

    static func relativeSchedule(
        seconds: TimeInterval,
        now: Date
    ) -> (description: String, nextRunAt: Date)? {
        guard seconds > 0 else { return nil }
        return (
            description: ThreadFollowUpScheduleParser.relativeDescription(seconds: seconds),
            nextRunAt: now.addingTimeInterval(seconds)
        )
    }

    static func tomorrowMorning(from date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.day = (components.day ?? 0) + 1
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date.addingTimeInterval(24 * 60 * 60)
    }
}
