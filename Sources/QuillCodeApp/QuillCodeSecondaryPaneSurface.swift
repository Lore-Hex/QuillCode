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

public struct ProjectExtensionManifestSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ProjectExtensionKind
    public var kindLabel: String
    public var name: String
    public var summary: String
    public var versionLabel: String?
    public var sourceURL: String?
    public var relativePath: String
    public var statusLabel: String
    public var transportLabel: String?
    public var launchCommand: String?
    public var updateCommand: String?
    public var serverLabel: String?
    public var protocolLabel: String?
    public var toolCountLabel: String?
    public var toolDescriptors: [MCPToolDescriptor]
    public var toolNames: [String]
    public var resourceCountLabel: String?
    public var resourceNames: [String]
    public var promptCountLabel: String?
    public var promptNames: [String]
    public var probeError: String?
    public var canStart: Bool
    public var canStop: Bool
    public var canUpdate: Bool
    public var startCommandID: String?
    public var stopCommandID: String?
    public var updateCommandID: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case kindLabel
        case name
        case summary
        case versionLabel
        case sourceURL
        case relativePath
        case statusLabel
        case transportLabel
        case launchCommand
        case updateCommand
        case serverLabel
        case protocolLabel
        case toolCountLabel
        case toolDescriptors
        case toolNames
        case resourceCountLabel
        case resourceNames
        case promptCountLabel
        case promptNames
        case probeError
        case canStart
        case canStop
        case canUpdate
        case startCommandID
        case stopCommandID
        case updateCommandID
    }

    public init(
        manifest: ProjectExtensionManifest,
        mcpServerStatus: MCPServerLifecycleStatus = .stopped,
        probeSummary: MCPServerProbeSummary? = nil
    ) {
        self.id = manifest.id
        self.kind = manifest.kind
        self.kindLabel = manifest.kind.title
        self.name = manifest.name
        self.summary = manifest.summary
        self.versionLabel = manifest.version.map { "v\($0)" }
        self.sourceURL = manifest.sourceURL
        self.relativePath = manifest.relativePath
        if manifest.isEnabled {
            if manifest.kind == .mcpServer {
                self.statusLabel = manifest.launchExecutable == nil ? "Missing command" : mcpServerStatus.title
            } else {
                self.statusLabel = "Discovered"
            }
        } else {
            self.statusLabel = "Disabled"
        }
        self.transportLabel = manifest.transport?.rawValue.uppercased()
        self.launchCommand = manifest.launchCommand
        self.updateCommand = manifest.updateCommand
        self.serverLabel = probeSummary?.serverLabel
        self.protocolLabel = probeSummary?.protocolVersion.map { "MCP \($0)" }
        self.toolCountLabel = probeSummary?.toolCountLabel
        let descriptors = Array((probeSummary?.toolDescriptors ?? []).prefix(4))
        self.toolDescriptors = descriptors
        self.toolNames = descriptors.isEmpty
            ? Array((probeSummary?.toolNames ?? []).prefix(4))
            : descriptors.map(\.name)
        self.resourceCountLabel = probeSummary?.resourceCountLabel
        self.resourceNames = Array((probeSummary?.resourceNames ?? []).prefix(4))
        self.promptCountLabel = probeSummary?.promptCountLabel
        self.promptNames = Array((probeSummary?.promptNames ?? []).prefix(4))
        self.probeError = probeSummary?.errorMessage
        self.canStart = manifest.kind == .mcpServer
            && manifest.isEnabled
            && manifest.launchExecutable != nil
            && !mcpServerStatus.isActive
        self.canStop = manifest.kind == .mcpServer && mcpServerStatus.isActive
        self.canUpdate = manifest.updateCommand != nil
        self.startCommandID = canStart ? "mcp-start:\(manifest.id)" : nil
        self.stopCommandID = canStop ? "mcp-stop:\(manifest.id)" : nil
        self.updateCommandID = canUpdate ? "extension-update:\(manifest.id)" : nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.kind = try container.decode(ProjectExtensionKind.self, forKey: .kind)
        self.kindLabel = try container.decode(String.self, forKey: .kindLabel)
        self.name = try container.decode(String.self, forKey: .name)
        self.summary = try container.decode(String.self, forKey: .summary)
        self.versionLabel = try container.decodeIfPresent(String.self, forKey: .versionLabel)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.relativePath = try container.decode(String.self, forKey: .relativePath)
        self.statusLabel = try container.decode(String.self, forKey: .statusLabel)
        self.transportLabel = try container.decodeIfPresent(String.self, forKey: .transportLabel)
        self.launchCommand = try container.decodeIfPresent(String.self, forKey: .launchCommand)
        self.updateCommand = try container.decodeIfPresent(String.self, forKey: .updateCommand)
        self.serverLabel = try container.decodeIfPresent(String.self, forKey: .serverLabel)
        self.protocolLabel = try container.decodeIfPresent(String.self, forKey: .protocolLabel)
        self.toolCountLabel = try container.decodeIfPresent(String.self, forKey: .toolCountLabel)
        self.toolDescriptors = try container.decodeIfPresent([MCPToolDescriptor].self, forKey: .toolDescriptors) ?? []
        self.toolNames = try container.decodeIfPresent([String].self, forKey: .toolNames) ?? []
        if self.toolDescriptors.isEmpty {
            self.toolDescriptors = self.toolNames.map { MCPToolDescriptor(name: $0) }
        }
        if self.toolNames.isEmpty {
            self.toolNames = self.toolDescriptors.map(\.name)
        }
        self.resourceCountLabel = try container.decodeIfPresent(String.self, forKey: .resourceCountLabel)
        self.resourceNames = try container.decodeIfPresent([String].self, forKey: .resourceNames) ?? []
        self.promptCountLabel = try container.decodeIfPresent(String.self, forKey: .promptCountLabel)
        self.promptNames = try container.decodeIfPresent([String].self, forKey: .promptNames) ?? []
        self.probeError = try container.decodeIfPresent(String.self, forKey: .probeError)
        self.canStart = try container.decode(Bool.self, forKey: .canStart)
        self.canStop = try container.decode(Bool.self, forKey: .canStop)
        self.canUpdate = try container.decodeIfPresent(Bool.self, forKey: .canUpdate) ?? false
        self.startCommandID = try container.decodeIfPresent(String.self, forKey: .startCommandID)
        self.stopCommandID = try container.decodeIfPresent(String.self, forKey: .stopCommandID)
        self.updateCommandID = try container.decodeIfPresent(String.self, forKey: .updateCommandID)
    }
}
