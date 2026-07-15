import Foundation

public enum WorkspaceCodeReviewPriority: String, Codable, Sendable, CaseIterable, Hashable, Comparable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    public var label: String { rawValue }

    private var sortOrder: Int {
        switch self {
        case .p0: 0
        case .p1: 1
        case .p2: 2
        case .p3: 3
        }
    }
}

public struct WorkspaceCodeReviewFinding: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var priority: WorkspaceCodeReviewPriority
    public var title: String
    public var body: String
    public var path: String
    public var line: Int?
    public var endLine: Int?

    public init(
        id: UUID = UUID(),
        priority: WorkspaceCodeReviewPriority,
        title: String,
        body: String,
        path: String,
        line: Int? = nil,
        endLine: Int? = nil
    ) {
        self.id = id
        self.priority = priority
        self.title = title
        self.body = body
        self.path = path
        self.line = line
        self.endLine = endLine
    }
}
