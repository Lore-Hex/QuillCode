import Foundation
import QuillCodeCore

public struct SidebarSurface: Codable, Sendable, Hashable {
    public var title: String
    public var items: [SidebarItemSurface]
    public var selectedThreadID: UUID?
    public var emptyTitle: String
    public var activeFilter: SidebarSavedFilterKind
    public var savedFilters: [SidebarSavedFilterSurface]
    public var isSelectionMode: Bool
    public var selectedThreadIDs: Set<UUID>
    public var selectionLabel: String
    public var bulkActions: [SidebarBulkActionSurface]

    public init(
        title: String = "Chats",
        items: [SidebarItemSurface],
        selectedThreadID: UUID?,
        emptyTitle: String = "No chats yet",
        activeFilter: SidebarSavedFilterKind = .all,
        isSelectionMode: Bool = false,
        selectedThreadIDs: Set<UUID> = [],
        bulkActions: [SidebarBulkActionSurface] = []
    ) {
        self.title = title
        self.items = items
        self.selectedThreadID = selectedThreadID
        self.activeFilter = activeFilter
        self.savedFilters = SidebarSavedFilterSurface.savedFilters(
            items: items,
            activeFilter: activeFilter
        )
        self.emptyTitle = items.isEmpty ? emptyTitle : activeFilter.emptyTitle
        self.isSelectionMode = isSelectionMode
        self.selectedThreadIDs = selectedThreadIDs
        self.selectionLabel = Self.selectionLabel(count: selectedThreadIDs.count)
        self.bulkActions = bulkActions
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case items
        case selectedThreadID
        case emptyTitle
        case activeFilter
        case savedFilters
        case isSelectionMode
        case selectedThreadIDs
        case selectionLabel
        case bulkActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Chats"
        self.items = try container.decodeIfPresent([SidebarItemSurface].self, forKey: .items) ?? []
        self.selectedThreadID = try container.decodeIfPresent(UUID.self, forKey: .selectedThreadID)
        self.emptyTitle = try container.decodeIfPresent(String.self, forKey: .emptyTitle) ?? "No chats yet"
        self.activeFilter = try container.decodeIfPresent(SidebarSavedFilterKind.self, forKey: .activeFilter) ?? .all
        self.savedFilters = try container.decodeIfPresent([SidebarSavedFilterSurface].self, forKey: .savedFilters)
            ?? SidebarSavedFilterSurface.savedFilters(items: self.items, activeFilter: self.activeFilter)
        self.isSelectionMode = try container.decodeIfPresent(Bool.self, forKey: .isSelectionMode) ?? false
        self.selectedThreadIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .selectedThreadIDs) ?? []
        self.selectionLabel = try container.decodeIfPresent(String.self, forKey: .selectionLabel)
            ?? Self.selectionLabel(count: self.selectedThreadIDs.count)
        self.bulkActions = try container.decodeIfPresent([SidebarBulkActionSurface].self, forKey: .bulkActions) ?? []
    }

    public func filteredItems(matching query: String) -> [SidebarItemSurface] {
        threadListBuilder.filteredItems(matching: query)
    }

    public var visibleItems: [SidebarItemSurface] {
        threadListBuilder.items(for: activeFilter)
    }

    public var pinnedItems: [SidebarItemSurface] {
        threadListBuilder.pinnedItems(for: activeFilter)
    }

    public var recentItems: [SidebarItemSurface] {
        threadListBuilder.recentItems(for: activeFilter)
    }

    public func recentSections(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SidebarThreadSectionSurface] {
        threadListBuilder.recentSections(for: activeFilter, now: now, calendar: calendar)
    }

    public var archivedItems: [SidebarItemSurface] {
        threadListBuilder.archivedItems(for: activeFilter)
    }

    private static func selectionLabel(count: Int) -> String {
        switch count {
        case 0:
            return "No chats selected"
        case 1:
            return "1 chat selected"
        default:
            return "\(count) chats selected"
        }
    }

    private var threadListBuilder: SidebarThreadListBuilder {
        SidebarThreadListBuilder(items: items)
    }
}

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
        activeFilter: SidebarSavedFilterKind
    ) -> [SidebarSavedFilterSurface] {
        SidebarSavedFilterKind.allCases.map { kind in
            SidebarSavedFilterSurface(
                kind: kind,
                count: items.filter { kind.includes(isPinned: $0.isPinned, isArchived: $0.isArchived) }.count,
                isActive: kind == activeFilter
            )
        }
    }
}

public struct SidebarThreadSectionSurface: Codable, Sendable, Hashable, Identifiable {
    public var title: String
    public var items: [SidebarItemSurface]

    public var id: String { title }

    public init(title: String, items: [SidebarItemSurface]) {
        self.title = title
        self.items = items
    }
}

public struct SidebarItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var searchText: String
    public var updatedAt: Date
    public var actions: [SidebarItemActionSurface]
    public var isSelected: Bool
    public var isBulkSelected: Bool
    public var isPinned: Bool
    public var isArchived: Bool

    public init(item: SidebarItem, selectedThreadID: UUID?, selectedThreadIDs: Set<UUID> = []) {
        self.id = item.id
        self.title = item.title
        self.subtitle = item.subtitle
        self.searchText = item.searchText
        self.updatedAt = item.updatedAt
        self.actions = Self.actions(for: item)
        self.isSelected = item.id == selectedThreadID
        self.isBulkSelected = selectedThreadIDs.contains(item.id)
        self.isPinned = item.isPinned
        self.isArchived = item.isArchived
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case searchText
        case updatedAt
        case actions
        case isSelected
        case isBulkSelected
        case isPinned
        case isArchived
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.searchText = try container.decode(String.self, forKey: .searchText)
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        self.actions = try container.decodeIfPresent([SidebarItemActionSurface].self, forKey: .actions) ?? []
        self.isSelected = try container.decode(Bool.self, forKey: .isSelected)
        self.isBulkSelected = try container.decodeIfPresent(Bool.self, forKey: .isBulkSelected) ?? false
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(searchText, forKey: .searchText)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(actions, forKey: .actions)
        try container.encode(isSelected, forKey: .isSelected)
        try container.encode(isBulkSelected, forKey: .isBulkSelected)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
    }

    private static func actions(for item: SidebarItem) -> [SidebarItemActionSurface] {
        if item.isArchived {
            return [
                SidebarItemActionSurface(kind: .unarchive, threadID: item.id),
                SidebarItemActionSurface(kind: .delete, threadID: item.id)
            ]
        }
        return [
            SidebarItemActionSurface(kind: .rename, threadID: item.id),
            SidebarItemActionSurface(kind: .duplicate, threadID: item.id),
            SidebarItemActionSurface(
                kind: item.isPinned ? .unpin : .pin,
                threadID: item.id
            ),
            SidebarItemActionSurface(kind: .archive, threadID: item.id),
            SidebarItemActionSurface(kind: .delete, threadID: item.id)
        ]
    }
}

public enum SidebarBulkActionKind: String, Codable, Sendable, Hashable {
    case select
    case selectAll
    case clearSelection
    case pin
    case unpin
    case archive
    case unarchive
    case delete

    public var title: String {
        switch self {
        case .select:
            return "Select"
        case .selectAll:
            return "Select all"
        case .clearSelection:
            return "Done"
        case .pin:
            return "Pin"
        case .unpin:
            return "Unpin"
        case .archive:
            return "Archive"
        case .unarchive:
            return "Unarchive"
        case .delete:
            return "Delete"
        }
    }
}

public struct SidebarBulkActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: SidebarBulkActionKind
    public var commandID: String
    public var title: String
    public var isEnabled: Bool
    public var isDestructive: Bool

    public var id: String { commandID }

    public init(
        kind: SidebarBulkActionKind,
        isEnabled: Bool = true,
        isDestructive: Bool = false
    ) {
        self.kind = kind
        self.commandID = Self.commandID(for: kind)
        self.title = kind.title
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
    }

    public static func commandID(for kind: SidebarBulkActionKind) -> String {
        switch kind {
        case .select:
            return "thread-selection-start"
        case .selectAll:
            return "thread-selection-select-all"
        case .clearSelection:
            return "thread-selection-clear"
        case .pin:
            return "thread-bulk-pin"
        case .unpin:
            return "thread-bulk-unpin"
        case .archive:
            return "thread-bulk-archive"
        case .unarchive:
            return "thread-bulk-unarchive"
        case .delete:
            return "thread-bulk-delete"
        }
    }
}

public enum SidebarItemActionKind: String, Codable, Sendable, Hashable {
    case rename
    case duplicate
    case pin
    case unpin
    case archive
    case unarchive
    case delete

    public var title: String {
        switch self {
        case .rename:
            return "Rename"
        case .duplicate:
            return "Duplicate"
        case .pin:
            return "Pin"
        case .unpin:
            return "Unpin"
        case .archive:
            return "Archive"
        case .unarchive:
            return "Unarchive"
        case .delete:
            return "Delete"
        }
    }
}

public struct SidebarItemActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var kind: SidebarItemActionKind
    public var threadID: UUID

    public var id: String {
        "\(threadID.uuidString)-\(kind.rawValue)"
    }

    public init(kind: SidebarItemActionKind, threadID: UUID) {
        self.kind = kind
        self.threadID = threadID
    }
}
