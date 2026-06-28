import Foundation
import QuillCodeCore
import QuillCodeTools

public struct WorkspaceExtensionsSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var items: [ProjectExtensionManifestSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public var pluginCount: Int { items.filter { $0.kind == .plugin }.count }
    public var skillCount: Int { items.filter { $0.kind == .skill }.count }
    public var mcpServerCount: Int { items.filter { $0.kind == .mcpServer }.count }
    public var availableCount: Int { items.filter { $0.statusLabel == "Available" }.count }

    public init(
        isVisible: Bool = false,
        manifests: [ProjectExtensionManifest] = [],
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:],
        emptyTitle: String = "No extension manifests found",
        emptySubtitle: String = "Add JSON manifests under .quillcode/plugins, .quillcode/skills, or .quillcode/mcp."
    ) {
        let projectedItems = manifests.map {
            ProjectExtensionManifestSurface(
                manifest: $0,
                mcpServerStatus: mcpServerStatuses[$0.id] ?? .stopped,
                probeSummary: mcpServerProbeSummaries[$0.id]
            )
        }
        self.isVisible = isVisible
        self.items = projectedItems
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.title = "Extensions"
        if manifests.isEmpty {
            self.subtitle = "No project-local plugins, skills, or MCP servers discovered"
        } else {
            let pluginCount = projectedItems.filter { $0.kind == .plugin }.count
            let skillCount = projectedItems.filter { $0.kind == .skill }.count
            let mcpServerCount = projectedItems.filter { $0.kind == .mcpServer }.count
            let availableCount = projectedItems.filter { $0.statusLabel == "Available" }.count
            let counts = [
                Self.countLabel(pluginCount, singular: "plugin"),
                Self.countLabel(skillCount, singular: "skill"),
                Self.countLabel(mcpServerCount, singular: "MCP server")
            ]
            let availability = availableCount == 0
                ? []
                : [Self.countLabel(availableCount, singular: "available extension")]
            self.subtitle = (counts + availability).joined(separator: " · ")
        }
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

public struct WorkspaceMemoriesSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var items: [MemoryNoteSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public var globalCount: Int { items.filter { $0.scope == .global }.count }
    public var projectCount: Int { items.filter { $0.scope == .project }.count }

    public init(
        isVisible: Bool = false,
        notes: [MemoryNote] = [],
        canEditProjectMemories: Bool = false,
        emptyTitle: String = "No memories loaded",
        emptySubtitle: String = "Add Markdown, text, or JSON notes under ~/.quillcode/memories or .quillcode/memories."
    ) {
        self.isVisible = isVisible
        self.items = notes.map { MemoryNoteSurface(note: $0, canEditProjectMemory: canEditProjectMemories) }
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.title = "Memories"
        if notes.isEmpty {
            self.subtitle = "No global or project memories are attached to this thread"
        } else {
            let globalCount = notes.filter { $0.scope == .global }.count
            let projectCount = notes.filter { $0.scope == .project }.count
            self.subtitle = [
                Self.countLabel(globalCount, singular: "global memory"),
                Self.countLabel(projectCount, singular: "project memory")
            ].joined(separator: " · ")
        }
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        if count == 1 { return "1 \(singular)" }
        if singular.hasSuffix("memory") {
            return "\(count) \(singular.dropLast("memory".count))memories"
        }
        return "\(count) \(singular)s"
    }
}

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
        let activeCount = automations.filter { $0.status == .active }.count
        let pausedCount = automations.filter { $0.status == .paused }.count
        self.isVisible = isVisible
        self.title = "Automations"
        self.subtitle = "Recurring work, follow-ups, monitors, and long-running agent jobs"
        self.statusLabel = Self.statusLabel(
            configuredCount: configuredWorkflows.count,
            activeCount: activeCount,
            pausedCount: pausedCount,
            plannedCount: workflows.count
        )
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.workflows = configuredWorkflows.isEmpty ? workflows : configuredWorkflows
        self.createThreadFollowUpCommand = createThreadFollowUpCommand
        self.createWorkspaceScheduleCommand = createWorkspaceScheduleCommand
        self.scheduleThreadFollowUpCommands = scheduleThreadFollowUpCommands
        self.scheduleWorkspaceScheduleCommands = scheduleWorkspaceScheduleCommands
    }

    private static func statusLabel(
        configuredCount: Int,
        activeCount: Int,
        pausedCount: Int,
        plannedCount: Int
    ) -> String {
        guard configuredCount > 0 else { return plannedCount == 0 ? "Empty" : "\(plannedCount) planned" }
        if activeCount > 0, pausedCount > 0 {
            return "\(activeCount) active · \(pausedCount) paused"
        }
        if activeCount > 0 {
            return activeCount == 1 ? "1 active" : "\(activeCount) active"
        }
        return pausedCount == 1 ? "1 paused" : "\(pausedCount) paused"
    }
}
