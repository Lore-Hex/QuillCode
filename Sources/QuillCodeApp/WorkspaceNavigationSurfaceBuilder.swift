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
    var selectionIsActive: Bool
    var selectedThreadIDs: Set<UUID>

    func surface() -> WorkspaceNavigationSurface {
        let resolvedSelectedThreadIDs = selectionIsActive ? selectedThreadIDs : []
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
                isSelectionMode: selectionIsActive,
                selectedThreadIDs: resolvedSelectedThreadIDs,
                bulkActions: sidebarBulkActions(selectedThreadIDs: resolvedSelectedThreadIDs)
            )
        )
    }

    private func projectItems() -> [ProjectItemSurface] {
        projects
            .sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            .map { ProjectItemSurface(project: $0, selectedProjectID: selectedProjectID) }
    }

    private func sidebarBulkActions(selectedThreadIDs: Set<UUID>) -> [SidebarBulkActionSurface] {
        guard selectionIsActive else {
            return [
                SidebarBulkActionSurface(
                    kind: .select,
                    isEnabled: !threads.isEmpty
                )
            ]
        }

        let selectedThreads = threads.filter { selectedThreadIDs.contains($0.id) }
        let hasSelection = !selectedThreads.isEmpty
        let hasPinnedSelection = selectedThreads.contains { $0.isPinned }
        let hasUnarchivedSelection = selectedThreads.contains { !$0.isArchived }
        let hasArchivedSelection = selectedThreads.contains { $0.isArchived }
        return [
            SidebarBulkActionSurface(kind: .clearSelection),
            SidebarBulkActionSurface(
                kind: .selectAll,
                isEnabled: selectedThreadIDs.count < sidebarItems.count
            ),
            SidebarBulkActionSurface(
                kind: .pin,
                isEnabled: hasUnarchivedSelection
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
