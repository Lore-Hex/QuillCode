import Foundation
import QuillCodeCore

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
        self.subtitle = Self.subtitle(for: notes)
    }

    private static func subtitle(for notes: [MemoryNote]) -> String {
        guard !notes.isEmpty else {
            return "No global or project memories are attached to this thread"
        }
        return WorkspacePaneSummaryFormatter.joinedCounts([
            (notes.filter { $0.scope == .global }.count, "global memory", "global memories"),
            (notes.filter { $0.scope == .project }.count, "project memory", "project memories")
        ])
    }
}
