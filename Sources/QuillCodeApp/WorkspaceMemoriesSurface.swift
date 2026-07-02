import Foundation
import QuillCodeCore

public struct WorkspaceMemoriesSurface: Codable, Sendable, Hashable {
    public var isVisible: Bool
    public var title: String
    public var subtitle: String
    public var items: [MemoryNoteSurface]
    public var conflicts: [MemoryConflictSurface]
    public var redactionReviews: [MemoryRedactionReviewSurface]
    public var emptyTitle: String
    public var emptySubtitle: String

    enum CodingKeys: String, CodingKey {
        case isVisible
        case title
        case subtitle
        case items
        case conflicts
        case redactionReviews
        case emptyTitle
        case emptySubtitle
    }

    public var globalCount: Int { items.filter { $0.scope == .global }.count }
    public var projectCount: Int { items.filter { $0.scope == .project }.count }
    public var conflictCount: Int { conflicts.count }
    public var redactionReviewCount: Int { redactionReviews.count }

    public init(
        isVisible: Bool = false,
        notes: [MemoryNote] = [],
        events: [ThreadEvent] = [],
        canEditProjectMemories: Bool = false,
        emptyTitle: String = "No memories loaded",
        emptySubtitle: String = "Add Markdown, text, or JSON notes under ~/.quillcode/memories or .quillcode/memories."
    ) {
        let items = notes.map { MemoryNoteSurface(note: $0, canEditProjectMemory: canEditProjectMemories) }
        let conflicts = MemoryConflictDetector.conflicts(
            notes: notes,
            canEditProjectMemory: canEditProjectMemories
        )
        let redactionReviews = MemoryRedactionReviewSurface.reviews(events: events)
        self.isVisible = isVisible
        self.items = items
        self.conflicts = conflicts
        self.redactionReviews = redactionReviews
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.title = "Memories"
        self.subtitle = Self.subtitle(
            for: notes,
            conflicts: conflicts,
            redactionReviews: redactionReviews
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Memories"
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            ?? "No global or project memories are attached to this thread"
        items = try container.decodeIfPresent([MemoryNoteSurface].self, forKey: .items) ?? []
        conflicts = try container.decodeIfPresent([MemoryConflictSurface].self, forKey: .conflicts) ?? []
        redactionReviews = try container.decodeIfPresent([MemoryRedactionReviewSurface].self, forKey: .redactionReviews) ?? []
        emptyTitle = try container.decodeIfPresent(String.self, forKey: .emptyTitle) ?? "No memories loaded"
        emptySubtitle = try container.decodeIfPresent(String.self, forKey: .emptySubtitle)
            ?? "Add Markdown, text, or JSON notes under ~/.quillcode/memories or .quillcode/memories."
    }

    private static func subtitle(
        for notes: [MemoryNote],
        conflicts: [MemoryConflictSurface],
        redactionReviews: [MemoryRedactionReviewSurface]
    ) -> String {
        guard !notes.isEmpty || !redactionReviews.isEmpty else {
            return "No global or project memories are attached to this thread"
        }
        var counts: [(count: Int, singular: String, plural: String?)] = notes.isEmpty ? [
            (0, "memory", "memories")
        ] : [
            (notes.filter { $0.scope == .global }.count, "global memory", "global memories"),
            (notes.filter { $0.scope == .project }.count, "project memory", "project memories")
        ]
        if !conflicts.isEmpty {
            counts.append((conflicts.count, "conflict", "conflicts"))
        }
        if !redactionReviews.isEmpty {
            counts.append((redactionReviews.count, "blocked attempt", "blocked attempts"))
        }
        return WorkspacePaneSummaryFormatter.joinedCounts(counts)
    }
}
