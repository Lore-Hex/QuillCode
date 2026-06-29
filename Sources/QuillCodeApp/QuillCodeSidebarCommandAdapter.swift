import Foundation

enum QuillCodeSidebarCommandAdapter {
    static func workspaceCommand(for action: SidebarBulkActionSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: action.commandID,
            title: action.title,
            category: WorkspaceCommandPalette.threadCategory,
            isEnabled: action.isEnabled
        )
    }

    static func workspaceCommand(for filter: SidebarSavedFilterSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: filter.commandID,
            title: "Show \(filter.title.lowercased()) chats",
            category: WorkspaceCommandPalette.threadCategory
        )
    }

    static func workspaceCommand(for savedSearch: SidebarSavedSearchSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: savedSearch.commandID,
            title: "Show \(savedSearch.title)",
            category: WorkspaceCommandPalette.threadCategory
        )
    }

    static func deleteWorkspaceCommand(for savedSearch: SidebarSavedSearchSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: SidebarSavedSearchSurface.deleteCommandID(for: savedSearch.id),
            title: "Delete \(savedSearch.title)",
            category: WorkspaceCommandPalette.threadCategory
        )
    }

    static func moveWorkspaceCommand(
        for savedSearch: SidebarSavedSearchSurface,
        direction: SidebarSavedSearchMoveDirection
    ) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: SidebarSavedSearchSurface.moveCommandID(for: savedSearch.id, direction: direction),
            title: "Move \(savedSearch.title) \(direction.rawValue)",
            category: WorkspaceCommandPalette.threadCategory,
            isEnabled: direction == .up ? savedSearch.canMoveUp : savedSearch.canMoveDown
        )
    }

    static func toggleSelectionCommand(for item: SidebarItemSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "thread-selection-toggle:\(item.id.uuidString)",
            title: item.isBulkSelected ? "Deselect chat" : "Select chat",
            category: WorkspaceCommandPalette.threadCategory
        )
    }
}
