import Foundation

public enum SidebarSavedFilterKind: String, Codable, Sendable, Hashable, CaseIterable {
    case all
    case pinned
    case recent
    case archived

    public var title: String {
        switch self {
        case .all:
            return "All"
        case .pinned:
            return "Pinned"
        case .recent:
            return "Recent"
        case .archived:
            return "Archived"
        }
    }

    public var commandID: String {
        "sidebar-filter:\(rawValue)"
    }

    public var emptyTitle: String {
        switch self {
        case .all:
            return "No chats yet"
        case .pinned:
            return "No pinned chats"
        case .recent:
            return "No recent chats"
        case .archived:
            return "No archived chats"
        }
    }

    public func includes(isPinned: Bool, isArchived: Bool) -> Bool {
        switch self {
        case .all:
            return true
        case .pinned:
            return isPinned && !isArchived
        case .recent:
            return !isPinned && !isArchived
        case .archived:
            return isArchived
        }
    }
}

public struct SidebarSavedFilterSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: SidebarSavedFilterKind
    public var commandID: String
    public var title: String
    public var count: Int
    public var isActive: Bool
    public var accessibilityLabel: String

    public var id: String { commandID }

    public init(
        kind: SidebarSavedFilterKind,
        count: Int,
        isActive: Bool
    ) {
        self.kind = kind
        self.commandID = kind.commandID
        self.title = kind.title
        self.count = count
        self.isActive = isActive
        self.accessibilityLabel = "\(kind.title) chats, \(count)"
    }

    public static func savedFilters(
        items: [SidebarItemSurface],
        activeFilter: SidebarSavedFilterKind,
        hasActiveCustomSavedSearch: Bool = false
    ) -> [SidebarSavedFilterSurface] {
        SidebarSavedFilterKind.allCases.map { kind in
            SidebarSavedFilterSurface(
                kind: kind,
                count: items.filter { kind.includes(isPinned: $0.isPinned, isArchived: $0.isArchived) }.count,
                isActive: !hasActiveCustomSavedSearch && kind == activeFilter
            )
        }
    }
}

public struct SidebarSavedSearch: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var query: String

    public init(
        id: UUID = UUID(),
        title: String,
        query: String
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !title.isEmpty && !query.isEmpty
    }
}

public enum SidebarSavedSearchMoveDirection: String, Codable, Sendable, Hashable {
    case up
    case down
}

public struct SidebarSavedSearchSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var commandID: String
    public var title: String
    public var query: String
    public var count: Int
    public var isActive: Bool
    public var canMoveUp: Bool
    public var canMoveDown: Bool
    public var accessibilityLabel: String
    public var emptyTitle: String

    public init(
        savedSearch: SidebarSavedSearch,
        count: Int,
        isActive: Bool,
        canMoveUp: Bool = false,
        canMoveDown: Bool = false
    ) {
        self.id = savedSearch.id
        self.commandID = Self.commandID(for: savedSearch.id)
        self.title = savedSearch.title
        self.query = savedSearch.query
        self.count = count
        self.isActive = isActive
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.accessibilityLabel = "\(savedSearch.title) saved search, \(count)"
        self.emptyTitle = "No chats matching \(savedSearch.title)"
    }

    public static func commandID(for id: UUID) -> String {
        "sidebar-saved-search:\(id.uuidString)"
    }

    public static func deleteCommandID(for id: UUID) -> String {
        "sidebar-saved-search-delete:\(id.uuidString)"
    }

    public static func moveCommandID(
        for id: UUID,
        direction: SidebarSavedSearchMoveDirection
    ) -> String {
        "sidebar-saved-search-move-\(direction.rawValue):\(id.uuidString)"
    }

    public static func savedSearches(
        _ savedSearches: [SidebarSavedSearch],
        items: [SidebarItemSurface],
        activeSavedSearchID: UUID?
    ) -> [SidebarSavedSearchSurface] {
        let validSavedSearches = savedSearches.filter(\.isValid)
        return validSavedSearches
            .enumerated()
            .map { index, savedSearch in
                SidebarSavedSearchSurface(
                    savedSearch: savedSearch,
                    count: SidebarThreadListBuilder(items: items)
                        .filteredItems(matching: savedSearch.query)
                        .count,
                    isActive: savedSearch.id == activeSavedSearchID,
                    canMoveUp: index > 0,
                    canMoveDown: index < validSavedSearches.count - 1
                )
            }
    }
}
