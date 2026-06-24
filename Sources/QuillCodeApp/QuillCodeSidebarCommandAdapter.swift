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

    static func toggleSelectionCommand(for item: SidebarItemSurface) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "thread-selection-toggle:\(item.id.uuidString)",
            title: item.isBulkSelected ? "Deselect chat" : "Select chat",
            category: WorkspaceCommandPalette.threadCategory
        )
    }
}
