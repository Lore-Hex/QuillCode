public struct ModelInfo: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var provider: String
    public var displayName: String
    public var category: String

    public init(id: String, provider: String, displayName: String, category: String) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.category = category
    }
}

public struct ModelSortKey: Sendable, Hashable, Comparable {
    public var recommendedRank: Int
    public var provider: String
    public var displayName: String
    public var id: String

    public init(recommendedRank: Int, provider: String, displayName: String, id: String) {
        self.recommendedRank = recommendedRank
        self.provider = provider
        self.displayName = displayName
        self.id = id
    }

    public static func < (lhs: ModelSortKey, rhs: ModelSortKey) -> Bool {
        if lhs.recommendedRank != rhs.recommendedRank {
            return lhs.recommendedRank < rhs.recommendedRank
        }
        if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
        if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
        return lhs.id < rhs.id
    }
}
