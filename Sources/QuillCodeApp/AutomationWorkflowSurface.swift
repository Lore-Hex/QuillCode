import Foundation
import QuillCodeCore

public struct AutomationWorkflowSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var statusLabel: String
    public var scheduleLabel: String
    public var runActionTitle: String?
    public var runCommandID: String?
    public var primaryActionTitle: String?
    public var primaryCommandID: String?
    public var deleteCommandID: String?

    public init(
        id: String,
        title: String,
        detail: String,
        statusLabel: String,
        scheduleLabel: String,
        runActionTitle: String? = nil,
        runCommandID: String? = nil,
        primaryActionTitle: String? = nil,
        primaryCommandID: String? = nil,
        deleteCommandID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
        self.scheduleLabel = scheduleLabel
        self.runActionTitle = runActionTitle
        self.runCommandID = runCommandID
        self.primaryActionTitle = primaryActionTitle
        self.primaryCommandID = primaryCommandID
        self.deleteCommandID = deleteCommandID
    }

    public init(automation: QuillAutomation) {
        let uuid = automation.id.uuidString
        self.id = uuid
        self.title = automation.title
        self.detail = automation.detail
        self.statusLabel = Self.statusLabel(for: automation)
        self.scheduleLabel = automation.scheduleDescription.isEmpty
            ? automation.scheduleKind.label
            : automation.scheduleDescription
        self.runActionTitle = Self.canRunNow(automation) ? "Run now" : nil
        self.runCommandID = Self.canRunNow(automation) ? "automation-run:\(uuid)" : nil
        self.primaryActionTitle = automation.status == .active ? "Pause" : "Resume"
        self.primaryCommandID = automation.status == .active
            ? "automation-pause:\(uuid)"
            : "automation-resume:\(uuid)"
        self.deleteCommandID = "automation-delete:\(uuid)"
    }

    private static func canRunNow(_ automation: QuillAutomation) -> Bool {
        automation.status == .active && automation.kind != .monitor
    }

    private static func statusLabel(for automation: QuillAutomation) -> String {
        guard automation.status == .active else { return automation.status.label }
        if let nextRunAt = automation.nextRunAt, nextRunAt <= Date() {
            return "Due"
        }
        if automation.lastRunAt != nil, automation.nextRunAt == nil {
            return "Ran"
        }
        return automation.status.label
    }

    public static let plannedWorkflows: [AutomationWorkflowSurface] = [
        AutomationWorkflowSurface(
            id: "thread-followups",
            title: "Thread follow-ups",
            detail: "Wake a conversation later with the same project, model, and context.",
            statusLabel: "Planned",
            scheduleLabel: "Heartbeat"
        ),
        AutomationWorkflowSurface(
            id: "workspace-schedules",
            title: "Workspace schedules",
            detail: "Run repeatable repo checks, local environment actions, or reports.",
            statusLabel: "Planned",
            scheduleLabel: "Cron"
        ),
        AutomationWorkflowSurface(
            id: "monitors",
            title: "Monitors",
            detail: "Watch CI, PRs, endpoints, or files and surface actionable changes.",
            statusLabel: "Planned",
            scheduleLabel: "Event"
        )
    ]
}
