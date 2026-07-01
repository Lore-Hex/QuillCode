import Foundation
import QuillCodeCore

public struct WorkspaceAutomationsSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var statusLabel: String
    public var emptyTitle: String
    public var emptySubtitle: String
    public var workflows: [AutomationWorkflowSurface]
    public var createThreadFollowUpCommand: WorkspaceCommandSurface?
    public var createWorkspaceScheduleCommand: WorkspaceCommandSurface?
    public var scheduleThreadFollowUpCommands: [WorkspaceCommandSurface]
    public var scheduleWorkspaceScheduleCommands: [WorkspaceCommandSurface]

    public init(
        isVisible: Bool = false,
        automations: [QuillAutomation] = [],
        createThreadFollowUpCommand: WorkspaceCommandSurface? = nil,
        createWorkspaceScheduleCommand: WorkspaceCommandSurface? = nil,
        scheduleThreadFollowUpCommands: [WorkspaceCommandSurface] = [],
        scheduleWorkspaceScheduleCommands: [WorkspaceCommandSurface] = [],
        workflows: [AutomationWorkflowSurface] = AutomationWorkflowSurface.plannedWorkflows,
        emptyTitle: String = "No automations yet",
        emptySubtitle: String = "Create scheduled follow-ups, workspace checks, and configured monitors for later runs."
    ) {
        let sortedAutomations = QuillAutomation.sortedForDisplay(automations)
        let configuredWorkflows = sortedAutomations.map(AutomationWorkflowSurface.init)
        self.isVisible = isVisible
        self.title = "Automations"
        self.subtitle = "Recurring work, follow-ups, monitors, and long-running agent jobs"
        self.statusLabel = Self.statusLabel(for: automations, configuredCount: configuredWorkflows.count, workflows: workflows)
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.workflows = configuredWorkflows.isEmpty ? workflows : configuredWorkflows
        self.createThreadFollowUpCommand = createThreadFollowUpCommand
        self.createWorkspaceScheduleCommand = createWorkspaceScheduleCommand
        self.scheduleThreadFollowUpCommands = scheduleThreadFollowUpCommands
        self.scheduleWorkspaceScheduleCommands = scheduleWorkspaceScheduleCommands
    }

    private static func statusLabel(
        for automations: [QuillAutomation],
        configuredCount: Int,
        workflows: [AutomationWorkflowSurface]
    ) -> String {
        guard configuredCount > 0 else { return workflows.isEmpty ? "Empty" : "\(workflows.count) planned" }
        let activeCount = automations.filter { $0.status == .active }.count
        let pausedCount = automations.filter { $0.status == .paused }.count
        if activeCount > 0, pausedCount > 0 {
            return WorkspacePaneSummaryFormatter.joinedCounts([
                (activeCount, "active", "active"),
                (pausedCount, "paused", "paused")
            ])
        }
        if activeCount > 0 {
            return WorkspacePaneSummaryFormatter.count(activeCount, singular: "active", plural: "active")
        }
        return WorkspacePaneSummaryFormatter.count(pausedCount, singular: "paused", plural: "paused")
    }
}
