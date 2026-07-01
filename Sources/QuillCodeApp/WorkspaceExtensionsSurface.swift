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
        self.subtitle = Self.subtitle(for: projectedItems, manifestCount: manifests.count)
    }

    private static func subtitle(
        for items: [ProjectExtensionManifestSurface],
        manifestCount: Int
    ) -> String {
        guard manifestCount > 0 else {
            return "No project-local plugins, skills, or MCP servers discovered"
        }
        let counts = WorkspacePaneSummaryFormatter.joinedCounts([
            (items.filter { $0.kind == .plugin }.count, "plugin", nil),
            (items.filter { $0.kind == .skill }.count, "skill", nil),
            (items.filter { $0.kind == .mcpServer }.count, "MCP server", nil)
        ])
        let availability = WorkspacePaneSummaryFormatter.optionalCount(
            items.filter { $0.statusLabel == "Available" }.count,
            singular: "available extension"
        )
        return ([counts] + availability).joined(separator: " · ")
    }
}
