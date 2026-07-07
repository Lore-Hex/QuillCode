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

    static func monitor(
        request: WorkspaceMonitorRequest,
        project: ProjectRef?,
        now: Date
    ) -> QuillAutomation {
        QuillAutomation(
            title: monitorTitle(for: request),
            detail: monitorDetail(for: request),
            kind: .monitor,
            scheduleKind: .event,
            scheduleDescription: request.kind.label,
            projectID: project?.id,
            eventSource: QuillAutomationEventSource(kind: request.kind, path: request.path),
            createdAt: now,
            updatedAt: now
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

    private static func monitorTitle(for request: WorkspaceMonitorRequest) -> String {
        switch request.kind {
        case .fileChange:
            return "Watch file: \(displayName(forPath: request.path))"
        case .urlLastModified:
            return "Watch URL header: \(displayName(forPath: request.path))"
        case .urlFeedUpdate:
            return "Watch feed: \(displayName(forPath: request.path))"
        }
    }

    private static func monitorDetail(for request: WorkspaceMonitorRequest) -> String {
        switch request.kind {
        case .fileChange:
            return "Watch \(request.path) for file changes."
        case .urlLastModified:
            return "Watch \(request.path) for Last-Modified header changes."
        case .urlFeedUpdate:
            return "Watch \(request.path) for RSS or Atom feed updates."
        }
    }

    private static func displayName(forPath path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host {
            let lastPath = url.pathComponents.last.flatMap { $0 == "/" ? nil : $0 }
            return lastPath.map { "\(host)/\($0)" } ?? host
        }
        return URL(fileURLWithPath: trimmed).lastPathComponent.nilIfEmpty ?? trimmed
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
