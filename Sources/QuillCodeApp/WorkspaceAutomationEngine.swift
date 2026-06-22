import Foundation
import QuillCodeCore

public struct AutomationsState: Sendable, Hashable {
    public var isVisible: Bool
    public var items: [QuillAutomation]

    public init(isVisible: Bool = false, items: [QuillAutomation] = []) {
        self.isVisible = isVisible
        self.items = items
    }
}

public struct AutomationRunReport: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID { followUpThreadID }
    public var automationID: UUID
    public var followUpThreadID: UUID
    public var title: String
    public var body: String

    public init(
        automationID: UUID,
        followUpThreadID: UUID,
        title: String,
        body: String
    ) {
        self.automationID = automationID
        self.followUpThreadID = followUpThreadID
        self.title = title
        self.body = body
    }
}

struct WorkspaceAutomationRunDraft: Sendable, Hashable {
    var automation: QuillAutomation
    var thread: ChatThread
    var selectedProjectID: UUID?
    var report: AutomationRunReport
}

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

    static func relativeSchedule(seconds: TimeInterval, now: Date) -> (description: String, nextRunAt: Date)? {
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

enum WorkspaceAutomationRunner {
    static func dueAutomationIDs(
        in automations: [QuillAutomation],
        now: Date,
        limit: Int
    ) -> [UUID] {
        automations
            .filter { automation in
                automation.status == .active
                    && automation.kind != .monitor
                    && automation.nextRunAt.map { $0 <= now } == true
            }
            .prefix(max(0, limit))
            .map(\.id)
    }

    static func updatedAfterRun(_ automation: QuillAutomation, now: Date) -> QuillAutomation {
        var updated = automation
        updated.lastRunAt = now
        updated.nextRunAt = automation.recurrence?.nextRun(after: now)
        updated.updatedAt = now
        return updated
    }

    static func threadFollowUpDraft(
        automation: QuillAutomation,
        source: ChatThread,
        selectedProjectID: UUID?,
        copiedMessages: [ChatMessage],
        now: Date
    ) -> WorkspaceAutomationRunDraft {
        let followUp = ChatThread(
            title: "Follow-up: \(source.title)",
            projectID: selectedProjectID,
            mode: source.mode,
            model: source.model,
            messages: copiedMessages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Automation ran: \(automation.title)",
                    payloadJSON: automation.id.uuidString
                ),
                .init(
                    kind: .notice,
                    summary: "Followed up from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
        return WorkspaceAutomationRunDraft(
            automation: updatedAfterRun(automation, now: now),
            thread: followUp,
            selectedProjectID: selectedProjectID,
            report: AutomationRunReport(
                automationID: automation.id,
                followUpThreadID: followUp.id,
                title: "QuillCode follow-up ready",
                body: "\(followUp.title) was created from \(source.title)."
            )
        )
    }

    static func workspaceScheduleDraft(
        automation: QuillAutomation,
        project: ProjectRef,
        mode: AgentMode,
        model: String,
        instructions: [ProjectInstruction],
        memories: [MemoryNote],
        now: Date
    ) -> WorkspaceAutomationRunDraft {
        let thread = ChatThread(
            title: "Scheduled check: \(project.name)",
            projectID: project.id,
            mode: mode,
            model: model,
            messages: [
                .init(
                    role: .user,
                    content: "Run the scheduled workspace check for \(project.name). Start with project status, recent changes, local actions, and anything needing attention."
                )
            ],
            events: [
                .init(
                    kind: .notice,
                    summary: "Automation ran: \(automation.title)",
                    payloadJSON: automation.id.uuidString
                )
            ],
            instructions: instructions,
            memories: memories
        )
        return WorkspaceAutomationRunDraft(
            automation: updatedAfterRun(automation, now: now),
            thread: thread,
            selectedProjectID: project.id,
            report: AutomationRunReport(
                automationID: automation.id,
                followUpThreadID: thread.id,
                title: "QuillCode workspace check ready",
                body: "\(thread.title) was created for \(project.name)."
            )
        )
    }
}
