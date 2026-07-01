import Foundation

enum WorkspaceHTMLSidebarThreadRenderer {
    static func render(_ sidebar: SidebarSurface, commands: [WorkspaceCommandSurface]) -> String {
        """
        <div class="sidebar-threads-zone" data-testid="sidebar-threads-zone">
          \(renderThreadHeader(sidebar))
          \(renderSavedFilters(sidebar))
          \(WorkspaceHTMLSidebarSavedSearchRenderer.render(sidebar, commands: commands))
          \(renderBulkToolbar(sidebar))
          \(renderThreadSections(sidebar))
        </div>
        """
    }

    private static func renderThreadHeader(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.items.isEmpty || sidebar.isSelectionMode else { return "" }
        return """
        <div class="sidebar-title-row" data-testid="sidebar-title-row">
          <h2>\(escape(sidebar.title))</h2>
          \(renderSelectionHeaderAction(sidebar))
        </div>
        """
    }

    private static func renderSavedFilters(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.items.isEmpty else { return "" }
        let filters = sidebar.savedFilters.map(renderSavedFilter).joined(separator: "\n")
        return """
        <div class="sidebar-filter-bar" data-testid="sidebar-filter-bar">
          \(filters)
        </div>
        """
    }

    private static func renderSavedFilter(_ filter: SidebarSavedFilterSurface) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            "\(filter.title) \(filter.count)",
            testID: "sidebar-filter",
            commandID: filter.commandID,
            hitTargetKind: .capsule,
            classes: [
                "sidebar-filter",
                filter.isActive ? "active" : ""
            ],
            ariaLabel: filter.accessibilityLabel,
            attributes: [
                ("aria-pressed", String(filter.isActive)),
                ("data-filter-id", filter.kind.rawValue)
            ]
        )
    }

    private static func renderBulkToolbar(_ sidebar: SidebarSurface) -> String {
        guard sidebar.isSelectionMode, !sidebar.bulkActions.isEmpty else { return "" }
        let actions = sidebar.bulkActions.map(renderBulkAction).joined(separator: "\n")
        return """
        <div\(selectionAttributes(for: sidebar))>
          <span data-testid="sidebar-selection-label">\(escape(sidebar.selectionLabel))</span>
          \(actions)
        </div>
        """
    }

    private static func selectionAttributes(for sidebar: SidebarSurface) -> String {
        " " + [
            #"data-testid="sidebar-selection""#,
            #"data-active="\#(sidebar.isSelectionMode)""#,
            #"data-selected-count="\#(sidebar.selectedThreadIDs.count)""#
        ]
        .joined(separator: " ")
    }

    private static func renderBulkAction(_ action: SidebarBulkActionSurface) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            action.title,
            testID: "sidebar-bulk-action",
            commandID: action.commandID,
            hitTargetKind: .text,
            disabled: !action.isEnabled,
            attributes: [
                ("data-action", action.kind.rawValue),
                ("data-destructive", String(action.isDestructive))
            ]
        )
    }

    private static func renderThreadSections(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.visibleItems.isEmpty else {
            return #"<p data-testid="sidebar-empty">\#(escape(sidebar.emptyTitle))</p>"#
        }

        return [
            renderSection(title: "Pinned", items: sidebar.pinnedItems),
            renderRecentSections(sidebar),
            renderSection(title: "Archived", items: sidebar.archivedItems)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func renderRecentSections(_ sidebar: SidebarSurface) -> String {
        sidebar.recentSections()
            .map { renderSection(title: $0.title, items: $0.items) }
            .joined(separator: "\n")
    }

    private static func renderSection(title: String, items: [SidebarItemSurface]) -> String {
        guard !items.isEmpty else { return "" }
        let rows = items.map(renderThreadRow).joined(separator: "\n")
        return """
        <section data-testid="sidebar-section">
          <h3 data-testid="sidebar-section-title">\(escape(title))</h3>
          \(rows)
        </section>
        """
    }

    private static func renderThreadRow(_ item: SidebarItemSurface) -> String {
        """
        <div data-testid="sidebar-thread-row">
          \(item.isBulkSelected ? "<span data-testid=\"sidebar-thread-selected\">Selected</span>" : "")
          <button\(WorkspaceHTMLPrimitives.buttonAttributes(
              testID: "sidebar-item",
              hitTargetKind: .row,
              classes: ["sidebar-item", item.isSelected ? "selected" : ""],
              attributes: [
                  ("data-thread-id", item.id.uuidString),
                  ("aria-current", item.isSelected ? "true" : "false")
              ]
          ))>
            <span>\(escape(item.title))</span>
            <small>\(escape(item.subtitle))</small>
          </button>
          <span data-testid="sidebar-item-actions">
            \(item.actions.map(renderAction).joined(separator: "\n"))
          </span>
        </div>
        """
    }

    private static func renderSelectionHeaderAction(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.visibleItems.isEmpty,
              !sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .select })
        else { return "" }
        return renderBulkAction(action)
    }

    private static func renderAction(_ action: SidebarItemActionSurface) -> String {
        WorkspaceHTMLPrimitives.button(
            action.kind.title,
            testID: "sidebar-thread-action",
            hitTargetKind: .icon,
            ariaLabel: action.kind.title,
            attributes: [
                ("data-action", action.kind.rawValue),
                ("data-thread-id", action.threadID.uuidString)
            ]
        )
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
