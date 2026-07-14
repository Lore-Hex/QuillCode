import Foundation

enum WorkspaceHTMLSidebarSavedSearchRenderer {
    static func render(_ sidebar: SidebarSurface, commands: [WorkspaceCommandSurface]) -> String {
        guard !sidebar.items.isEmpty else { return "" }
        let createCommandID = WorkspaceCommandAction.sidebarSavedSearchCreate.rawValue
        guard commands.contains(where: { $0.id == createCommandID }) || !sidebar.customSavedSearches.isEmpty else {
            return ""
        }
        let rows = sidebar.customSavedSearches.map(renderSavedSearch).joined(separator: "\n")
        return """
        <section class="sidebar-filter-section sidebar-saved-search-bar" data-testid="sidebar-saved-search-bar">
          <h3>Saved searches</h3>
          \(rows)
          \(WorkspaceHTMLPrimitives.commandButton(
              "Save current search…",
              testID: "sidebar-saved-search-create",
              commandID: createCommandID,
              hitTargetKind: .row,
              classes: ["sidebar-saved-search-create"],
              ariaLabel: "Save sidebar search"
          ))
        </section>
        """
    }

    private static func renderSavedSearch(_ savedSearch: SidebarSavedSearchSurface) -> String {
        """
        <div class="sidebar-saved-search-row" data-testid="sidebar-saved-search-row">
          \(renderSearchChip(savedSearch))
          \(renderMoveButton(savedSearch, direction: .up))
          \(renderMoveButton(savedSearch, direction: .down))
          \(renderDeleteButton(savedSearch))
        </div>
        """
    }

    private static func renderSearchChip(_ savedSearch: SidebarSavedSearchSurface) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            "\(savedSearch.title) \(savedSearch.count)",
            testID: "sidebar-saved-search",
            commandID: savedSearch.commandID,
            hitTargetKind: .capsule,
            classes: [
                "sidebar-filter",
                "sidebar-saved-search",
                savedSearch.isActive ? "active" : ""
            ],
            ariaLabel: savedSearch.accessibilityLabel,
            attributes: [
                ("aria-pressed", String(savedSearch.isActive)),
                ("data-saved-search-id", savedSearch.id.uuidString),
                ("data-query", savedSearch.query)
            ]
        )
    }

    private static func renderMoveButton(
        _ savedSearch: SidebarSavedSearchSurface,
        direction: SidebarSavedSearchMoveDirection
    ) -> String {
        let title = direction == .up ? "Up" : "Down"
        return WorkspaceHTMLPrimitives.commandButton(
            title,
            testID: "sidebar-saved-search-move-\(direction.rawValue)",
            commandID: SidebarSavedSearchSurface.moveCommandID(for: savedSearch.id, direction: direction),
            hitTargetKind: .icon,
            classes: ["sidebar-saved-search-move"],
            ariaLabel: "Move saved search \(savedSearch.title) \(direction.rawValue)",
            disabled: direction == .up ? !savedSearch.canMoveUp : !savedSearch.canMoveDown,
            attributes: [
                ("data-saved-search-id", savedSearch.id.uuidString)
            ]
        )
    }

    private static func renderDeleteButton(_ savedSearch: SidebarSavedSearchSurface) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            "Delete",
            testID: "sidebar-saved-search-delete",
            commandID: SidebarSavedSearchSurface.deleteCommandID(for: savedSearch.id),
            hitTargetKind: .icon,
            classes: ["sidebar-saved-search-delete"],
            ariaLabel: "Delete saved search \(savedSearch.title)",
            attributes: [
                ("data-saved-search-id", savedSearch.id.uuidString)
            ]
        )
    }
}
