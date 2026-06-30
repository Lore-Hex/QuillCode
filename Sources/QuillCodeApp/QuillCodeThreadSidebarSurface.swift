import Foundation
import QuillCodeCore

public struct SidebarSurface: Codable, Sendable, Hashable {
    public var title: String
    public var items: [SidebarItemSurface]
    public var selectedThreadID: UUID?
    public var emptyTitle: String
    public var activeFilter: SidebarSavedFilterKind
    public var activeSavedSearchID: UUID?
    public var savedFilters: [SidebarSavedFilterSurface]
    public var customSavedSearches: [SidebarSavedSearchSurface]
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
        activeSavedSearchID: UUID? = nil,
        customSavedSearches: [SidebarSavedSearch] = [],
        isSelectionMode: Bool = false,
        selectedThreadIDs: Set<UUID> = [],
        bulkActions: [SidebarBulkActionSurface] = []
    ) {
        self.title = title
        self.items = items
        self.selectedThreadID = selectedThreadID
        self.activeFilter = activeFilter
        self.activeSavedSearchID = customSavedSearches.contains { $0.id == activeSavedSearchID } ? activeSavedSearchID : nil
        self.savedFilters = SidebarSavedFilterSurface.savedFilters(
            items: items,
            activeFilter: activeFilter,
            hasActiveCustomSavedSearch: self.activeSavedSearchID != nil
        )
        self.customSavedSearches = SidebarSavedSearchSurface.savedSearches(
            customSavedSearches,
            items: items,
            activeSavedSearchID: self.activeSavedSearchID
        )
        self.emptyTitle = Self.resolvedEmptyTitle(
            items: items,
            defaultEmptyTitle: emptyTitle,
            activeFilter: activeFilter,
            activeSavedSearch: self.customSavedSearches.first(where: \.isActive)
        )
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
        case activeSavedSearchID
        case savedFilters
        case customSavedSearches
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
        self.activeSavedSearchID = try container.decodeIfPresent(UUID.self, forKey: .activeSavedSearchID)
        self.savedFilters = try container.decodeIfPresent([SidebarSavedFilterSurface].self, forKey: .savedFilters)
            ?? SidebarSavedFilterSurface.savedFilters(
                items: self.items,
                activeFilter: self.activeFilter,
                hasActiveCustomSavedSearch: self.activeSavedSearchID != nil
            )
        self.customSavedSearches = try container.decodeIfPresent([SidebarSavedSearchSurface].self, forKey: .customSavedSearches) ?? []
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
        activeSavedSearchQuery.map { threadListBuilder.filteredItems(matching: $0) }
            ?? threadListBuilder.items(for: activeFilter)
    }

    public var pinnedItems: [SidebarItemSurface] {
        activeSavedSearchQuery.map { threadListBuilder.pinnedItems(matching: $0) }
            ?? threadListBuilder.pinnedItems(for: activeFilter)
    }

    public var recentItems: [SidebarItemSurface] {
        activeSavedSearchQuery.map { threadListBuilder.recentItems(matching: $0) }
            ?? threadListBuilder.recentItems(for: activeFilter)
    }

    public func recentSections(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SidebarThreadSectionSurface] {
        activeSavedSearchQuery.map {
            threadListBuilder.recentSections(matching: $0, now: now, calendar: calendar)
        } ?? threadListBuilder.recentSections(for: activeFilter, now: now, calendar: calendar)
    }

    public var archivedItems: [SidebarItemSurface] {
        activeSavedSearchQuery.map { threadListBuilder.archivedItems(matching: $0) }
            ?? threadListBuilder.archivedItems(for: activeFilter)
    }

    private var activeSavedSearchQuery: String? {
        customSavedSearches.first(where: \.isActive)?.query
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

    private static func resolvedEmptyTitle(
        items: [SidebarItemSurface],
        defaultEmptyTitle: String,
        activeFilter: SidebarSavedFilterKind,
        activeSavedSearch: SidebarSavedSearchSurface?
    ) -> String {
        guard !items.isEmpty else { return defaultEmptyTitle }
        if let activeSavedSearch {
            return activeSavedSearch.emptyTitle
        }
        return activeFilter.emptyTitle
    }

    private var threadListBuilder: SidebarThreadListBuilder {
        SidebarThreadListBuilder(items: items)
    }
}
