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

    public init(
        isVisible: Bool = false,
        manifests: [ProjectExtensionManifest] = [],
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:],
        emptyTitle: String = "No extension manifests found",
        emptySubtitle: String = "Add JSON manifests under .quillcode/plugins, .quillcode/skills, or .quillcode/mcp."
    ) {
        self.isVisible = isVisible
        self.items = manifests.map {
            ProjectExtensionManifestSurface(
                manifest: $0,
                mcpServerStatus: mcpServerStatuses[$0.id] ?? .stopped,
                probeSummary: mcpServerProbeSummaries[$0.id]
            )
        }
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.title = "Extensions"
        if manifests.isEmpty {
            self.subtitle = "No project-local plugins, skills, or MCP servers discovered"
        } else {
            let pluginCount = manifests.filter { $0.kind == .plugin }.count
            let skillCount = manifests.filter { $0.kind == .skill }.count
            let mcpCount = manifests.filter { $0.kind == .mcpServer }.count
            self.subtitle = [
                Self.countLabel(pluginCount, singular: "plugin"),
                Self.countLabel(skillCount, singular: "skill"),
                Self.countLabel(mcpCount, singular: "MCP server")
            ].joined(separator: " · ")
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
        emptyTitle: String = "No memories loaded",
        emptySubtitle: String = "Add Markdown, text, or JSON notes under ~/.quillcode/memories or .quillcode/memories."
    ) {
        self.isVisible = isVisible
        self.items = notes.map(MemoryNoteSurface.init)
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
        emptySubtitle: String = "Create scheduled follow-ups, workspace checks, and monitors once the automation runtime lands."
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
        self.id = automation.id.uuidString
        self.title = automation.title
        self.detail = automation.detail
        self.statusLabel = Self.statusLabel(for: automation)
        self.scheduleLabel = automation.scheduleDescription.isEmpty
            ? automation.scheduleKind.label
            : automation.scheduleDescription
        self.runActionTitle = automation.status == .active && automation.kind != .monitor
            ? "Run now"
            : nil
        self.runCommandID = automation.status == .active && automation.kind != .monitor
            ? "automation-run:\(uuid)"
            : nil
        self.primaryActionTitle = automation.status == .active ? "Pause" : "Resume"
        self.primaryCommandID = automation.status == .active
            ? "automation-pause:\(uuid)"
            : "automation-resume:\(uuid)"
        self.deleteCommandID = "automation-delete:\(uuid)"
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

public struct MemoryNoteSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var scope: MemoryScope
    public var scopeLabel: String
    public var title: String
    public var preview: String
    public var relativePath: String
    public var byteCountLabel: String
    public var canDelete: Bool
    public var deleteCommandID: String?

    public init(note: MemoryNote) {
        self.id = note.id
        self.scope = note.scope
        self.scopeLabel = note.scope.title
        self.title = note.title
        self.preview = Self.preview(note.content, wasTruncated: note.wasTruncated)
        self.relativePath = note.relativePath
        self.byteCountLabel = note.wasTruncated
            ? "\(note.byteCount) bytes, truncated"
            : "\(note.byteCount) bytes"
        self.canDelete = note.scope == .global
        self.deleteCommandID = note.scope == .global ? "memory-delete:\(note.id)" : nil
    }

    private static func preview(_ content: String, wasTruncated: Bool) -> String {
        let normalized = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 180 else { return normalized }
        let end = normalized.index(normalized.startIndex, offsetBy: 180)
        return "\(normalized[..<end])..."
    }
}
