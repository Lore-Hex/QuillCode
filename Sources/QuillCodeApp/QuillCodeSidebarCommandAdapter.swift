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

    static func toggleSelectionCommand(for item: SidebarItemSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "thread-selection-toggle:\(item.id.uuidString)",
            title: item.isBulkSelected ? "Deselect chat" : "Select chat",
            category: WorkspaceCommandPalette.threadCategory
        )
    }
}
