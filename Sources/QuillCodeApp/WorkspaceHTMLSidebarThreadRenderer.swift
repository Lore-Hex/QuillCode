enum WorkspaceHTMLSidebarThreadRenderer {
    static func render(_ sidebar: SidebarSurface, commands: [WorkspaceCommandSurface]) -> String {
        """
        \(renderHeader(sidebar))
        \(renderSavedFilters(sidebar))
        \(renderSavedSearches(sidebar, commands: commands))
        \(renderBulkToolbar(sidebar))
        \(renderSections(sidebar))
        """
    }

    private static func renderHeader(_ sidebar: SidebarSurface) -> String {
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
        let filters = sidebar.savedFilters
            .map(renderSavedFilter)
            .joined(separator: "\n")
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

    private static func renderSavedSearches(
        _ sidebar: SidebarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        guard !sidebar.items.isEmpty else { return "" }
        let createCommandID = WorkspaceCommandAction.sidebarSavedSearchCreate.rawValue
        guard commands.contains(where: { $0.id == createCommandID }) || !sidebar.customSavedSearches.isEmpty else {
            return ""
        }

        let savedSearches = sidebar.customSavedSearches
            .map(renderSavedSearch)
            .joined(separator: "\n")
        return """
        <div class="sidebar-filter-bar sidebar-saved-search-bar" data-testid="sidebar-saved-search-bar">
          <div class="sidebar-saved-search-header">
            <span class="sidebar-saved-search-label">Saved searches</span>
            \(renderCreateSavedSearchButton(commandID: createCommandID))
          </div>
          \(savedSearches.isEmpty ? emptySavedSearchesHTML : savedSearches)
        </div>
        """
    }

    private static func renderSavedSearch(_ savedSearch: SidebarSavedSearchSurface) -> String {
        """
        <div class="sidebar-saved-search-row" data-testid="sidebar-saved-search-row">
          \(renderSavedSearchFilter(savedSearch))
          \(renderSavedSearchMoveButton(savedSearch, direction: .up))
          \(renderSavedSearchMoveButton(savedSearch, direction: .down))
          \(renderSavedSearchDeleteButton(savedSearch))
        </div>
        """
    }

    private static func renderSavedSearchFilter(_ savedSearch: SidebarSavedSearchSurface) -> String {
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

    private static func renderSavedSearchMoveButton(
        _ savedSearch: SidebarSavedSearchSurface,
        direction: SidebarSavedSearchMoveDirection
    ) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            direction.title,
            testID: "sidebar-saved-search-move-\(direction.rawValue)",
            commandID: SidebarSavedSearchSurface.moveCommandID(for: savedSearch.id, direction: direction),
            hitTargetKind: .icon,
            classes: ["sidebar-saved-search-move"],
            ariaLabel: "Move saved search \(savedSearch.title) \(direction.rawValue)",
            disabled: !savedSearch.canMove(direction),
            attributes: [("data-saved-search-id", savedSearch.id.uuidString)]
        )
    }

    private static func renderSavedSearchDeleteButton(_ savedSearch: SidebarSavedSearchSurface) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            "Delete",
            testID: "sidebar-saved-search-delete",
            commandID: SidebarSavedSearchSurface.deleteCommandID(for: savedSearch.id),
            hitTargetKind: .icon,
            classes: ["sidebar-saved-search-delete"],
            ariaLabel: "Delete saved search \(savedSearch.title)",
            attributes: [("data-saved-search-id", savedSearch.id.uuidString)]
        )
    }

    private static func renderCreateSavedSearchButton(commandID: String) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            "Save",
            testID: "sidebar-saved-search-create",
            commandID: commandID,
            hitTargetKind: .text,
            classes: ["sidebar-saved-search-create"],
            ariaLabel: "Save sidebar search"
        )
    }

    private static var emptySavedSearchesHTML: String {
        #"<p class="sidebar-saved-search-empty" data-testid="sidebar-saved-search-empty">No saved searches yet</p>"#
    }

    private static func renderBulkToolbar(_ sidebar: SidebarSurface) -> String {
        guard sidebar.isSelectionMode, !sidebar.bulkActions.isEmpty else { return "" }
        let actions = sidebar.bulkActions
            .map(renderBulkAction)
            .joined(separator: "\n")
        return """
        <div\(bulkToolbarAttributes(sidebar))>
          <span data-testid="sidebar-selection-label">\(escape(sidebar.selectionLabel))</span>
          \(actions)
        </div>
        """
    }

    private static func bulkToolbarAttributes(_ sidebar: SidebarSurface) -> String {
        let attributes = [
            #"data-testid="sidebar-selection""#,
            #"data-active="\#(sidebar.isSelectionMode)""#,
            #"data-selected-count="\#(sidebar.selectedThreadIDs.count)""#
        ]
        return " " + attributes.joined(separator: " ")
    }

    private static func renderBulkAction(_ action: SidebarBulkActionSurface) -> String {
        WorkspaceHTMLPrimitives.commandButton(
            action.title,
            testID: "sidebar-bulk-action",
            commandID: action.commandID,
            hitTargetKind: .text,
            disabled: !action.isEnabled,
            attributes: bulkActionAttributes(action)
        )
    }

    private static func renderSelectionHeaderAction(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.visibleItems.isEmpty,
              !sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .select })
        else { return "" }
        return renderBulkAction(action)
    }

    private static func renderSections(_ sidebar: SidebarSurface) -> String {
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
        return """
        <section data-testid="sidebar-section">
          <h3 data-testid="sidebar-section-title">\(escape(title))</h3>
          \(items.map(renderRow).joined(separator: "\n"))
        </section>
        """
    }

    private static func renderRow(_ item: SidebarItemSurface) -> String {
        """
        <div data-testid="sidebar-thread-row">
          \(item.isBulkSelected ? selectedThreadIndicatorHTML : "")
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
            \(item.actions.map(renderThreadAction).joined(separator: "\n"))
          </span>
        </div>
        """
    }

    private static var selectedThreadIndicatorHTML: String {
        #"<span data-testid="sidebar-thread-selected">Selected</span>"#
    }

    private static func renderThreadAction(_ action: SidebarItemActionSurface) -> String {
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

    private static func bulkActionAttributes(_ action: SidebarBulkActionSurface) -> [(String, String)] {
        [
            ("data-action", action.kind.rawValue),
            ("data-destructive", String(action.isDestructive))
        ]
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}

private extension SidebarSavedSearchMoveDirection {
    var title: String {
        switch self {
        case .up:
            return "Up"
        case .down:
            return "Down"
        }
    }
}

private extension SidebarSavedSearchSurface {
    func canMove(_ direction: SidebarSavedSearchMoveDirection) -> Bool {
        switch direction {
        case .up:
            return canMoveUp
        case .down:
            return canMoveDown
        }
    }
}
