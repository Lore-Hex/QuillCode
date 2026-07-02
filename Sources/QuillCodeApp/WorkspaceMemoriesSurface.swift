import Foundation
import QuillCodeCore

public struct WorkspaceMemoriesSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var items: [MemoryNoteSurface]
    public var conflicts: [MemoryConflictSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    public var globalCount: Int { items.filter { $0.scope == .global }.count }
    public var projectCount: Int { items.filter { $0.scope == .project }.count }
    public var conflictCount: Int { conflicts.count }

    public init(
        isVisible: Bool = false,
        notes: [MemoryNote] = [],
        canEditProjectMemories: Bool = false,
        emptyTitle: String = "No memories loaded",
        emptySubtitle: String = "Add Markdown, text, or JSON notes under ~/.quillcode/memories or .quillcode/memories."
    ) {
        let items = notes.map { MemoryNoteSurface(note: $0, canEditProjectMemory: canEditProjectMemories) }
        let conflicts = MemoryConflictDetector.conflicts(
            notes: notes,
            canEditProjectMemory: canEditProjectMemories
        )
        self.isVisible = isVisible
        self.items = items
        self.conflicts = conflicts
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.title = "Memories"
        self.subtitle = Self.subtitle(for: notes, conflicts: conflicts)
    }

    private static func subtitle(for notes: [MemoryNote], conflicts: [MemoryConflictSurface]) -> String {
        guard !notes.isEmpty else {
            return "No global or project memories are attached to this thread"
        }
        var counts: [(count: Int, singular: String, plural: String?)] = [
            (notes.filter { $0.scope == .global }.count, "global memory", "global memories"),
            (notes.filter { $0.scope == .project }.count, "project memory", "project memories")
        ]
        if !conflicts.isEmpty {
            counts.append((conflicts.count, "conflict", "conflicts"))
        }
        return WorkspacePaneSummaryFormatter.joinedCounts(counts)
    }
}
