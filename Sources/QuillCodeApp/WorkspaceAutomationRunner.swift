import Foundation
import QuillCodeCore

enum WorkspaceAutomationRunner {
    static func dueAutomationIDs(
        in automations: [QuillAutomation],
        now: Date,
        limit: Int
    ) -> [UUID] {
        dueAutomationTriggers(
            in: automations,
            now: now,
            limit: limit
        ).map(\.automationID)
    }

    static func dueAutomationTriggers(
        in automations: [QuillAutomation],
        now: Date,
        eventSources: [UUID: any AutomationEventSource] = [:],
        limit: Int
    ) -> [WorkspaceAutomationTrigger] {
        automations
            .compactMap { automation -> WorkspaceAutomationTrigger? in
                guard automation.status == .active else { return nil }
                if automation.nextRunAt.map({ $0 <= now }) == true {
                    return trigger(for: automation)
                }
                guard automation.kind == .monitor,
                      automation.scheduleKind == .event,
                      let eventSource = eventSources[automation.id],
                      let event = eventSource.pendingEvent(since: automation.lastRunAt)
                else {
                    return nil
                }
                return trigger(for: automation, eventDescription: event)
            }
            .prefix(max(0, limit))
            .map(\.self)
    }

    static func updatedAfterRun(
        _ automation: QuillAutomation,
        now: Date,
        calendar: Calendar = .current
    ) -> QuillAutomation {
        var updated = automation
        updated.lastRunAt = now
        updated.nextRunAt = automation.recurrence?.nextRun(after: now, calendar: calendar)
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
                automationRanEvent(for: automation),
                .init(
                    kind: .notice,
                    summary: "Followed up from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
        return runDraft(
            automation: updatedAfterRun(automation, now: now),
            thread: followUp,
            selectedProjectID: selectedProjectID,
            title: "QuillCode follow-up ready",
            body: "\(followUp.title) was created from \(source.title)."
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
                    content: workspaceScheduleMessage(for: project)
                )
            ],
            events: [
                automationRanEvent(for: automation)
            ],
            instructions: instructions,
            memories: memories
        )
        return runDraft(
            automation: updatedAfterRun(automation, now: now),
            thread: thread,
            selectedProjectID: project.id,
            title: "QuillCode workspace check ready",
            body: "\(thread.title) was created for \(project.name)."
        )
    }

    static func monitorDraft(
        automation: QuillAutomation,
        project: ProjectRef?,
        mode: AgentMode,
        model: String,
        instructions: [ProjectInstruction],
        memories: [MemoryNote],
        triggerDescription: String? = nil,
        now: Date
    ) -> WorkspaceAutomationRunDraft {
        let projectSentence = project.map { "Use the \($0.name) workspace context." }
        let triggerSentence = triggerDescription.map { "Trigger: \($0)" }
        let messageLines = [
            "Run the monitor \"\(automation.title)\".",
            "Watch condition: \(automation.detail)",
            triggerSentence,
            projectSentence,
            "Report what changed, whether action is needed, and the next concrete step."
        ].compactMap(\.self)

        let thread = ChatThread(
            title: "Monitor: \(automation.title)",
            projectID: project?.id,
            mode: mode,
            model: model,
            messages: [
                .init(role: .user, content: messageLines.joined(separator: "\n"))
            ],
            events: monitorEvents(for: automation, triggerDescription: triggerDescription),
            instructions: instructions,
            memories: memories
        )
        return runDraft(
            automation: updatedAfterRun(automation, now: now),
            thread: thread,
            selectedProjectID: project?.id,
            title: "QuillCode monitor check ready",
            body: project.map {
                "\(thread.title) was created for \($0.name)."
            } ?? "\(thread.title) was created."
        )
    }

    private static func trigger(
        for automation: QuillAutomation,
        eventDescription: String? = nil
    ) -> WorkspaceAutomationTrigger {
        WorkspaceAutomationTrigger(
            automationID: automation.id,
            eventDescription: eventDescription
        )
    }

    private static func automationRanEvent(for automation: QuillAutomation) -> ThreadEvent {
        .init(
            kind: .notice,
            summary: "Automation ran: \(automation.title)",
            payloadJSON: automation.id.uuidString
        )
    }

    private static func monitorEvents(
        for automation: QuillAutomation,
        triggerDescription: String?
    ) -> [ThreadEvent] {
        [
            automationRanEvent(for: automation),
            .init(
                kind: .notice,
                summary: monitorStartSummary(for: automation),
                payloadJSON: automation.kind.rawValue
            ),
            triggerDescription.map {
                .init(
                    kind: .notice,
                    summary: "Monitor trigger: \($0)",
                    payloadJSON: automation.eventSource?.path
                )
            }
        ].compactMap(\.self)
    }

    private static func workspaceScheduleMessage(for project: ProjectRef) -> String {
        """
        Run the scheduled workspace check for \(project.name). Start with project status, recent changes, \
        local actions, and anything needing attention.
        """
    }

    private static func runDraft(
        automation: QuillAutomation,
        thread: ChatThread,
        selectedProjectID: UUID?,
        title: String,
        body: String
    ) -> WorkspaceAutomationRunDraft {
        WorkspaceAutomationRunDraft(
            automation: automation,
            thread: thread,
            selectedProjectID: selectedProjectID,
            report: AutomationRunReport(
                automationID: automation.id,
                followUpThreadID: thread.id,
                title: title,
                body: body
            )
        )
    }

    private static func monitorStartSummary(for automation: QuillAutomation) -> String {
        let schedule = automation.scheduleDescription.isEmpty
            ? automation.scheduleKind.label
            : automation.scheduleDescription
        return "Monitor check started from \(schedule)"
    }
}
