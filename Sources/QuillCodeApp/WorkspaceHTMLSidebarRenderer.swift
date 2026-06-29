import Foundation

enum WorkspaceHTMLSidebarRenderer {
    static func render(
        projects: ProjectListSurface,
        sidebar: SidebarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        """
        <aside class="sidebar" data-testid="sidebar" aria-label="Projects and chats">
          <div class="sidebar-actions" data-testid="sidebar-compose-zone" aria-label="Primary chat actions">
            \(renderPrimaryActions(commands))
          </div>
          <div class="sidebar-threads-zone" data-testid="sidebar-threads-zone">
            \(renderThreadHeader(sidebar))
            \(renderSavedFilters(sidebar))
            \(renderSavedSearches(sidebar, commands: commands))
            \(renderBulkToolbar(sidebar))
            \(renderThreadSections(sidebar))
          </div>
          <div class="sidebar-projects-zone" data-testid="sidebar-projects-zone">
            <div class="sidebar-section-title">
              <h2>\(escape(projects.title))</h2>
              \(WorkspaceHTMLPrimitives.button(
                  "+",
                  testID: "add-project-button",
                  hitTargetKind: .icon,
                  ariaLabel: "Open project"
              ))
            </div>
            \(renderProjects(projects))
          </div>
          \(renderFooter(commands))
        </aside>
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

    private static func renderProjects(_ projects: ProjectListSurface) -> String {
        guard !projects.items.isEmpty else {
            return #"<p data-testid="project-empty">\#(escape(projects.emptyTitle))</p>"#
        }

        return projects.items.map { project in
            """
            <button\(WorkspaceHTMLPrimitives.buttonAttributes(
                testID: "project-item",
                hitTargetKind: .row,
                classes: ["project-item", project.isSelected ? "selected" : ""],
                attributes: [
                    ("data-project-id", project.id.uuidString),
                    ("aria-current", project.isSelected ? "true" : "false")
                ]
            ))>
              <span>\(escape(project.name))\(project.isRemote ? #" <small data-testid="project-connection-kind">SSH Remote</small>"# : "")</span>
              <small>\(escape(project.path))</small>
            </button>
            """
        }.joined(separator: "\n")
    }

    private static func renderThreadSections(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.visibleItems.isEmpty else {
            return #"<p data-testid="sidebar-empty">\#(escape(sidebar.emptyTitle))</p>"#
        }

        return [
            renderSection(title: "Pinned", items: sidebar.pinnedItems),
            sidebar.recentSections().map { renderSection(title: $0.title, items: $0.items) }.joined(separator: "\n"),
            renderSection(title: "Archived", items: sidebar.archivedItems)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private static func renderSavedFilters(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.items.isEmpty else { return "" }
        let filters = sidebar.savedFilters.map { filter in
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
        }.joined(separator: "\n")
        return """
        <div class="sidebar-filter-bar" data-testid="sidebar-filter-bar">
          \(filters)
        </div>
        """
    }

    private static func renderSavedSearches(_ sidebar: SidebarSurface, commands: [WorkspaceCommandSurface]) -> String {
        guard !sidebar.items.isEmpty else { return "" }
        let createCommandID = WorkspaceCommandAction.sidebarSavedSearchCreate.rawValue
        guard commands.contains(where: { $0.id == createCommandID }) || !sidebar.customSavedSearches.isEmpty else {
            return ""
        }
        let savedSearches = sidebar.customSavedSearches.map { savedSearch in
            """
            <div class="sidebar-saved-search-row" data-testid="sidebar-saved-search-row">
              \(WorkspaceHTMLPrimitives.commandButton(
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
              ))
              \(WorkspaceHTMLPrimitives.commandButton(
                  "Delete",
                  testID: "sidebar-saved-search-delete",
                  commandID: SidebarSavedSearchSurface.deleteCommandID(for: savedSearch.id),
                  hitTargetKind: .icon,
                  classes: ["sidebar-saved-search-delete"],
                  ariaLabel: "Delete saved search \(savedSearch.title)",
                  attributes: [
                      ("data-saved-search-id", savedSearch.id.uuidString)
                  ]
              ))
            </div>
            """
        }.joined(separator: "\n")
        return """
        <div class="sidebar-filter-bar sidebar-saved-search-bar" data-testid="sidebar-saved-search-bar">
          <div class="sidebar-saved-search-header">
            <span class="sidebar-saved-search-label">Saved searches</span>
            \(WorkspaceHTMLPrimitives.commandButton(
                "Save",
                testID: "sidebar-saved-search-create",
                commandID: createCommandID,
                hitTargetKind: .text,
                classes: ["sidebar-saved-search-create"],
                ariaLabel: "Save sidebar search"
            ))
          </div>
          \(savedSearches.isEmpty ? #"<p class="sidebar-saved-search-empty" data-testid="sidebar-saved-search-empty">No saved searches yet</p>"# : savedSearches)
        </div>
        """
    }

    private static func renderPrimaryActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.primaryCommandIDs
            .compactMap { commandID in
                commands.first { $0.id == commandID }
            }
            .map { command in
                let testID = QuillCodeSidebarCommandPresentation.htmlTestID(for: command.id)
                let icon = QuillCodeSidebarCommandPresentation.htmlIconToken(for: command.id)
                let title = QuillCodeSidebarCommandPresentation.displayTitle(for: command)
                return WorkspaceHTMLPrimitives.commandButton(
                    title,
                    testID: testID,
                    commandID: command.id,
                    hitTargetKind: .row,
                    classes: ["sidebar-action"],
                    disabled: !command.isEnabled,
                    attributes: [
                        ("data-primary", "true"),
                        ("data-icon", icon)
                    ]
                )
            }
            .joined(separator: "\n")
    }

    private static func renderSection(title: String, items: [SidebarItemSurface]) -> String {
        guard !items.isEmpty else { return "" }
        let rows = items.map { item in
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
        }.joined(separator: "\n")
        return """
        <section data-testid="sidebar-section">
          <h3 data-testid="sidebar-section-title">\(escape(title))</h3>
          \(rows)
        </section>
        """
    }

    private static func renderBulkToolbar(_ sidebar: SidebarSurface) -> String {
        guard sidebar.isSelectionMode, !sidebar.bulkActions.isEmpty else { return "" }
        let actions = sidebar.bulkActions.map { action in
            WorkspaceHTMLPrimitives.commandButton(
                action.title,
                testID: "sidebar-bulk-action",
                commandID: action.commandID,
                disabled: !action.isEnabled,
                attributes: [
                    ("data-action", action.kind.rawValue),
                    ("data-destructive", String(action.isDestructive))
                ]
            )
        }.joined(separator: "\n")
        return """
        <div data-testid="sidebar-selection" data-active="\(sidebar.isSelectionMode)" data-selected-count="\(sidebar.selectedThreadIDs.count)">
          <span data-testid="sidebar-selection-label">\(escape(sidebar.selectionLabel))</span>
          \(actions)
        </div>
        """
    }

    private static func renderSelectionHeaderAction(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.visibleItems.isEmpty,
              !sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .select })
        else { return "" }
        return WorkspaceHTMLPrimitives.commandButton(
            action.title,
            testID: "sidebar-bulk-action",
            commandID: action.commandID,
            disabled: !action.isEnabled,
            attributes: [
                ("data-action", action.kind.rawValue),
                ("data-destructive", String(action.isDestructive))
            ]
        )
    }

    private static func renderAction(_ action: SidebarItemActionSurface) -> String {
        WorkspaceHTMLPrimitives.button(
            action.kind.title,
            testID: "sidebar-thread-action",
            attributes: [
                ("data-action", action.kind.rawValue),
                ("data-thread-id", action.threadID.uuidString)
            ]
        )
    }

    private static func renderFooter(_ commands: [WorkspaceCommandSurface]) -> String {
        """
        <div class="sidebar-footer" aria-label="Workspace tools">
          <details class="sidebar-tools-menu" data-testid="sidebar-tools-menu">
            \(WorkspaceHTMLPrimitives.summary(
                "Tools",
                testID: "sidebar-tools-button",
                ariaLabel: "Tools",
                title: "Tools"
            ))
            <div class="sidebar-tools-popover" role="menu">
              \(renderUtilityActions(commands))
            </div>
          </details>
          \(WorkspaceHTMLPrimitives.button(
              "Settings",
              testID: "settings-button",
              hitTargetKind: .row,
              classes: ["sidebar-settings-button"],
              ariaLabel: "Settings",
              title: "Settings"
          ))
        </div>
        """
    }

    private static func renderUtilityActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.visibleUtilityCommandGroups(from: commands)
            .map { group in
                """
                <section class="sidebar-tools-section" data-testid="sidebar-tools-section" data-command-group="\(escape(group.id))">
                  <h3 data-testid="sidebar-tools-section-title">\(escape(group.title))</h3>
                  \(group.commands.map(renderUtilityAction).joined(separator: "\n"))
                </section>
                """
            }
            .joined(separator: "\n")
    }

    private static func renderUtilityAction(_ command: WorkspaceCommandSurface) -> String {
        let testID = QuillCodeSidebarCommandPresentation.htmlTestID(for: command.id)
        let icon = QuillCodeSidebarCommandPresentation.htmlIconToken(for: command.id)
        let title = QuillCodeSidebarCommandPresentation.displayTitle(for: command)
        return WorkspaceHTMLPrimitives.commandButton(
            title,
            testID: testID,
            commandID: command.id,
            hitTargetKind: .row,
            classes: ["sidebar-tool-action"],
            ariaLabel: title,
            title: title,
            role: "menuitem",
            disabled: !command.isEnabled,
            attributes: [("data-icon", icon)]
        )
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
