public enum MemoryScope: String, Codable, Sendable, Hashable {
    case global
    case project

    public var title: String {
        switch self {
        case .global:
            return "Global"
        case .project:
            return "Project"
        }
    }
}

public struct MemoryNote: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var scope: MemoryScope
    public var title: String
    public var content: String
    public var relativePath: String
    public var byteCount: Int
    public var wasTruncated: Bool

    public init(
        id: String,
        scope: MemoryScope,
        title: String,
        content: String,
        relativePath: String,
        byteCount: Int,
        wasTruncated: Bool = false
    ) {
        self.id = id
        self.scope = scope
        self.title = title
        self.content = content
        self.relativePath = relativePath
        self.byteCount = byteCount
        self.wasTruncated = wasTruncated
    }
}
