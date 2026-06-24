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
            \(renderBulkToolbar(sidebar))
            \(renderThreadSections(sidebar))
          </div>
          <div class="sidebar-projects-zone" data-testid="sidebar-projects-zone">
            <div class="sidebar-section-title">
              <h2>\(escape(projects.title))</h2>
              <button type="button" data-testid="add-project-button" aria-label="Open project">+</button>
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
            <button class="project-item\(project.isSelected ? " selected" : "")" data-testid="project-item" data-project-id="\(project.id.uuidString)" aria-current="\(project.isSelected ? "true" : "false")">
              <span>\(escape(project.name))\(project.isRemote ? #" <small data-testid="project-connection-kind">SSH Remote</small>"# : "")</span>
              <small>\(escape(project.path))</small>
            </button>
            """
        }.joined(separator: "\n")
    }

    private static func renderThreadSections(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.items.isEmpty else {
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

    private static func renderPrimaryActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.primaryCommandIDs
            .compactMap { commandID in
                commands.first { $0.id == commandID }
            }
            .map { command in
                let testID = QuillCodeSidebarCommandPresentation.htmlTestID(for: command.id)
                let icon = QuillCodeSidebarCommandPresentation.htmlIconToken(for: command.id)
                let title = QuillCodeSidebarCommandPresentation.displayTitle(for: command)
                let disabled = command.isEnabled ? "" : #" disabled aria-disabled="true""#
                return #"<button class="sidebar-action" type="button" data-testid="\#(escape(testID))" data-primary="true" data-icon="\#(escape(icon))" data-command-id="\#(escape(command.id))"\#(disabled)>\#(escape(title))</button>"#
            }
            .joined(separator: "\n")
    }

    private static func renderSection(title: String, items: [SidebarItemSurface]) -> String {
        guard !items.isEmpty else { return "" }
        let rows = items.map { item in
            """
            <div data-testid="sidebar-thread-row">
              \(item.isBulkSelected ? "<span data-testid=\"sidebar-thread-selected\">Selected</span>" : "")
              <button class="sidebar-item\(item.isSelected ? " selected" : "")" data-testid="sidebar-item" data-thread-id="\(item.id.uuidString)" aria-current="\(item.isSelected ? "true" : "false")">
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
            """
            <button type="button" data-testid="sidebar-bulk-action" data-command-id="\(escape(action.commandID))" data-action="\(escape(action.kind.rawValue))" data-destructive="\(action.isDestructive)" \(action.isEnabled ? "" : "disabled")>\(escape(action.title))</button>
            """
        }.joined(separator: "\n")
        return """
        <div data-testid="sidebar-selection" data-active="\(sidebar.isSelectionMode)" data-selected-count="\(sidebar.selectedThreadIDs.count)">
          <span data-testid="sidebar-selection-label">\(escape(sidebar.selectionLabel))</span>
          \(actions)
        </div>
        """
    }

    private static func renderSelectionHeaderAction(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.items.isEmpty,
              !sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .select })
        else { return "" }
        return """
        <button type="button" data-testid="sidebar-bulk-action" data-command-id="\(escape(action.commandID))" data-action="\(escape(action.kind.rawValue))" data-destructive="\(action.isDestructive)" \(action.isEnabled ? "" : "disabled")>\(escape(action.title))</button>
        """
    }

    private static func renderAction(_ action: SidebarItemActionSurface) -> String {
        """
        <button type="button" data-testid="sidebar-thread-action" data-action="\(escape(action.kind.rawValue))" data-thread-id="\(action.threadID.uuidString)">\(escape(action.kind.title))</button>
        """
    }

    private static func renderFooter(_ commands: [WorkspaceCommandSurface]) -> String {
        """
        <div class="sidebar-footer" aria-label="Workspace tools">
          <details class="sidebar-tools-menu" data-testid="sidebar-tools-menu">
            <summary data-testid="sidebar-tools-button" aria-label="Tools" title="Tools">Tools</summary>
            <div class="sidebar-tools-popover" role="menu">
              \(renderUtilityActions(commands))
            </div>
          </details>
          <button class="sidebar-settings-button" type="button" data-testid="settings-button" aria-label="Settings" title="Settings">Settings</button>
        </div>
        """
    }

    private static func renderUtilityActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.utilityCommandIDs
            .compactMap { commandID in
                commands.first { $0.id == commandID }
            }
            .map { command in
                let testID = QuillCodeSidebarCommandPresentation.htmlTestID(for: command.id)
                let icon = QuillCodeSidebarCommandPresentation.htmlIconToken(for: command.id)
                let title = QuillCodeSidebarCommandPresentation.displayTitle(for: command)
                let disabled = command.isEnabled ? "" : #" disabled aria-disabled="true""#
                return #"<button class="sidebar-tool-action" type="button" data-testid="\#(escape(testID))" role="menuitem" aria-label="\#(escape(title))" title="\#(escape(title))" data-icon="\#(escape(icon))" data-command-id="\#(escape(command.id))"\#(disabled)>\#(escape(title))</button>"#
            }
            .joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
