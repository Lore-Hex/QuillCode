import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

public struct WorkspaceExtensionsSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var focusedKind: ProjectExtensionKind?
    public var title: String
    public var subtitle: String
    public var items: [ProjectExtensionManifestSurface]
    public var totalItems: [ProjectExtensionManifestSurface]
    public var hookItems: [ProjectPluginHookSurface]
    public var totalHookItems: [ProjectPluginHookSurface]
    public var emptyTitle: String
    public var emptySubtitle: String
    public var workflowRecording: WorkflowRecordingStatus?

    public var pluginCount: Int { totalItems.filter { $0.kind == .plugin }.count }
    public var skillCount: Int { totalItems.filter { $0.kind == .skill }.count }
    public var mcpServerCount: Int { totalItems.filter { $0.kind == .mcpServer }.count }
    public var hookCount: Int { totalHookItems.count }
    public var availableCount: Int { totalItems.filter { $0.statusLabel == "Available" }.count }

    public init(
        isVisible: Bool = false,
        focusedKind: ProjectExtensionKind? = nil,
        manifests: [ProjectExtensionManifest] = [],
        hooks: [ProjectPluginHook] = [],
        mcpServerStatuses: [String: MCPServerLifecycleStatus] = [:],
        mcpServerProbeSummaries: [String: MCPServerProbeSummary] = [:],
        workflowRecording: WorkflowRecordingStatus? = nil,
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
        let projectedHooks = hooks.map(ProjectPluginHookSurface.init)
        let visibleItems = focusedKind.map { kind in
            kind == .hook ? [] : projectedItems.filter { $0.kind == kind }
        } ?? projectedItems
        let visibleHooks = focusedKind == nil || focusedKind == .hook ? projectedHooks : []
        self.isVisible = isVisible
        self.focusedKind = focusedKind
        self.items = visibleItems
        self.totalItems = projectedItems
        self.hookItems = visibleHooks
        self.totalHookItems = projectedHooks
        self.emptyTitle = Self.emptyTitle(focusedKind: focusedKind, fallback: emptyTitle)
        self.emptySubtitle = Self.emptySubtitle(focusedKind: focusedKind, fallback: emptySubtitle)
        self.workflowRecording = workflowRecording
        self.title = Self.title(focusedKind: focusedKind)
        self.subtitle = Self.subtitle(
            for: visibleItems,
            allItems: projectedItems,
            focusedKind: focusedKind,
            manifestCount: manifests.count,
            hookCount: hooks.count
        )
    }

    private static func subtitle(
        for items: [ProjectExtensionManifestSurface],
        allItems: [ProjectExtensionManifestSurface],
        focusedKind: ProjectExtensionKind?,
        manifestCount: Int,
        hookCount: Int
    ) -> String {
        guard manifestCount > 0 || hookCount > 0 else {
            return "No project-local plugins, skills, MCP servers, or hooks discovered"
        }
        if let focusedKind {
            if focusedKind == .hook {
                return WorkspacePaneSummaryFormatter.count(hookCount, singular: "hook")
            }
            let singular = focusedKind.singularSummaryName
            let availability = WorkspacePaneSummaryFormatter.optionalCount(
                items.filter { $0.statusLabel == "Available" }.count,
                singular: "available \(singular)"
            )
            return ([WorkspacePaneSummaryFormatter.count(items.count, singular: singular)] + availability)
                .joined(separator: " · ")
        }
        var summaryCounts: [(count: Int, singular: String, plural: String?)] = [
            (allItems.filter { $0.kind == .plugin }.count, "plugin", nil),
            (allItems.filter { $0.kind == .skill }.count, "skill", nil),
            (allItems.filter { $0.kind == .mcpServer }.count, "MCP server", nil)
        ]
        if hookCount > 0 {
            summaryCounts.append((hookCount, "hook", nil))
        }
        let counts = WorkspacePaneSummaryFormatter.joinedCounts(summaryCounts)
        let availability = WorkspacePaneSummaryFormatter.optionalCount(
            allItems.filter { $0.statusLabel == "Available" }.count,
            singular: "available extension"
        )
        return ([counts] + availability).joined(separator: " · ")
    }

    private static func title(focusedKind: ProjectExtensionKind?) -> String {
        switch focusedKind {
        case .plugin:
            return "Plugins"
        case .skill:
            return "Skills"
        case .mcpServer:
            return "MCP Servers"
        case .hook:
            return "Hooks"
        case nil:
            return "Extensions"
        }
    }

    private static func emptyTitle(focusedKind: ProjectExtensionKind?, fallback: String) -> String {
        guard let focusedKind else { return fallback }
        return "No \(focusedKind.singularSummaryName)s found"
    }

    private static func emptySubtitle(focusedKind: ProjectExtensionKind?, fallback: String) -> String {
        guard let focusedKind else { return fallback }
        if focusedKind == .hook {
            return "Add hooks.json or inline hooks to project config, or install a plugin that provides hooks."
        }
        return "Add \(focusedKind.singularSummaryName) manifests under \(focusedKind.defaultManifestDirectory)."
    }
}

private extension ProjectExtensionKind {
    var singularSummaryName: String {
        switch self {
        case .plugin:
            return "plugin"
        case .skill:
            return "skill"
        case .mcpServer:
            return "MCP server"
        case .hook:
            return "hook"
        }
    }

    var defaultManifestDirectory: String {
        switch self {
        case .plugin:
            return ".quillcode/plugins"
        case .skill:
            return ".quillcode/skills"
        case .mcpServer:
            return ".quillcode/mcp"
        case .hook:
            return ".quillcode/hooks.json"
        }
    }
}
