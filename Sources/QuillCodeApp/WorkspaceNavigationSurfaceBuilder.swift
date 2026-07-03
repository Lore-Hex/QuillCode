import Foundation
import QuillCodeCore

struct WorkspaceNavigationSurface: Sendable, Hashable {
    var projects: ProjectListSurface
    var sidebar: SidebarSurface
}

struct WorkspaceNavigationSurfaceBuilder {
    var projects: [ProjectRef]
    var selectedProjectID: UUID?
    var sidebarItems: [SidebarItem]
    var selectedThreadID: UUID?
    var threads: [ChatThread]
    var activeSidebarFilter: SidebarSavedFilterKind
    var activeSidebarSavedSearchID: UUID? = nil
    var sidebarSavedSearches: [SidebarSavedSearch] = []
    var selectionIsActive: Bool
    var selectedThreadIDs: Set<UUID>

    func surface() -> WorkspaceNavigationSurface {
        let visibleSidebarItems = filteredSidebarItems()
        let visibleSidebarItemIDs = Set(visibleSidebarItems.map(\.id))
        let resolvedSelectedThreadIDs = selectionIsActive
            ? selectedThreadIDs.intersection(visibleSidebarItemIDs)
            : []
        return WorkspaceNavigationSurface(
            projects: ProjectListSurface(
                items: projectItems(),
                selectedProjectID: selectedProjectID
            ),
            sidebar: SidebarSurface(
                items: sidebarItems.map {
                    SidebarItemSurface(
                        item: $0,
                        selectedThreadID: selectedThreadID,
                        selectedThreadIDs: resolvedSelectedThreadIDs
                    )
                },
                selectedThreadID: selectedThreadID,
                activeFilter: activeSidebarFilter,
                activeSavedSearchID: activeSidebarSavedSearchID,
                customSavedSearches: sidebarSavedSearches,
                isSelectionMode: selectionIsActive,
                selectedThreadIDs: resolvedSelectedThreadIDs,
                bulkActions: sidebarBulkActions(
                    selectedThreadIDs: resolvedSelectedThreadIDs,
                    visibleSidebarItems: visibleSidebarItems
                ),
                attention: attentionSection()
            )
        )
    }

    /// Build the morning-triage Attention section from the actual threads, ranked by the shared pure
    /// `AttentionModel`. The section's cursor prefers the sidebar's selected thread when that thread is
    /// itself an attention row, so keyboard triage and click selection stay in sync.
    private func attentionSection() -> AttentionSectionSurface {
        let model = AttentionModel.build(from: threads, selectedThreadID: selectedThreadID)
        return AttentionSectionSurface(model: model)
    }

    private func projectItems() -> [ProjectItemSurface] {
        projects
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .map { ProjectItemSurface(project: $0, selectedProjectID: selectedProjectID) }
    }

    private func filteredSidebarItems() -> [SidebarItem] {
        if let activeSearch = sidebarSavedSearches.first(where: { $0.id == activeSidebarSavedSearchID }) {
            return sidebarItems.filter {
                SidebarThreadListBuilder.matches($0, query: activeSearch.query)
            }
        }
        return sidebarItems.filter {
            activeSidebarFilter.includes(isPinned: $0.isPinned, isArchived: $0.isArchived)
        }
    }

    private func sidebarBulkActions(
        selectedThreadIDs: Set<UUID>,
        visibleSidebarItems: [SidebarItem]
    ) -> [SidebarBulkActionSurface] {
        guard selectionIsActive else {
            return [
                SidebarBulkActionSurface(
                    kind: .select,
                    isEnabled: !visibleSidebarItems.isEmpty
                )
            ]
        }

        let selectedThreads = threads.filter { selectedThreadIDs.contains($0.id) }
        let visibleSelectedCount = visibleSidebarItems.filter { selectedThreadIDs.contains($0.id) }.count
        let hasSelection = !selectedThreads.isEmpty
        let hasPinnedSelection = selectedThreads.contains { $0.isPinned }
        let hasUnpinnedUnarchivedSelection = selectedThreads.contains { !$0.isPinned && !$0.isArchived }
        let hasUnarchivedSelection = selectedThreads.contains { !$0.isArchived }
        let hasArchivedSelection = selectedThreads.contains { $0.isArchived }
        return [
            SidebarBulkActionSurface(kind: .clearSelection),
            SidebarBulkActionSurface(
                kind: .selectAll,
                isEnabled: visibleSelectedCount < visibleSidebarItems.count
            ),
            SidebarBulkActionSurface(
                kind: .pin,
                isEnabled: hasUnpinnedUnarchivedSelection
            ),
            SidebarBulkActionSurface(
                kind: .unpin,
                isEnabled: hasPinnedSelection
            ),
            SidebarBulkActionSurface(
                kind: .archive,
                isEnabled: hasUnarchivedSelection
            ),
            SidebarBulkActionSurface(
                kind: .unarchive,
                isEnabled: hasArchivedSelection
            ),
            SidebarBulkActionSurface(
                kind: .delete,
                isEnabled: hasSelection,
                isDestructive: true
            )
        ]
    }
}
