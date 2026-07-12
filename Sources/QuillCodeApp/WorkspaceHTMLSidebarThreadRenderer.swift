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
            renderAttentionSection(sidebar.attention),
            renderSection(title: "Pinned", items: sidebar.pinnedItems),
            renderRecentSections(sidebar),
            renderSection(title: "Archived", items: sidebar.archivedItems)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    /// The morning-triage "Attention" section (issue #877): severity-ranked rows with the run-integrity
    /// verdict badge, unseen-turn count, and j/k/Enter/a/d keyboard triage. Rendered empty (nothing) when
    /// no thread needs attention. Mirrors the native `QuillCodeAttentionSectionView` exactly.
    private static func renderAttentionSection(_ attention: AttentionSectionSurface) -> String {
        guard !attention.isEmpty else { return "" }
        let rows = attention.rows.map { renderAttentionRow($0, selectedThreadID: attention.selectedThreadID) }
            .joined(separator: "\n")
        return """
        <section data-testid="attention-section" aria-label="Attention">
          <h3 data-testid="sidebar-section-title">Attention</h3>
          \(rows)
        </section>
        """
    }

    private static func renderAttentionRow(_ row: AttentionRowSurface, selectedThreadID: UUID?) -> String {
        let isCursor = row.threadID == selectedThreadID
        let unseen = row.unseenLabel.map {
            #"<span data-testid="attention-unseen">\#(escape($0))</span>"#
        } ?? ""
        return """
        <div data-testid="attention-row" data-thread-id="\(row.threadID.uuidString)" \
        data-verdict="\(row.verdict.rawValue)" data-cursor="\(isCursor ? "true" : "false")" \
        aria-current="\(isCursor ? "true" : "false")">
          <span data-testid="attention-verdict" data-verdict="\(row.verdict.rawValue)">\(escape(row.badgeLabel))</span>
          <span data-testid="attention-title">\(escape(row.title))</span>
          \(unseen)
        </div>
        """
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
                  ("aria-current", item.isSelected ? "true" : "false"),
                  ("data-run-status", item.runStatusLabel ?? "")
              ]
          ))>
            <span class="sidebar-title-line"><span>\(escape(item.title))</span>\(renderRunStatus(item.runStatusLabel))</span>
            <small>\(escape(item.subtitle))</small>
            \(renderWorktreeChip(item.worktree))
          </button>
          <span data-testid="sidebar-item-actions">
            \(item.actions.map(renderAction).joined(separator: "\n"))
          </span>
        </div>
        """
    }

    private static func renderRunStatus(_ status: String?) -> String {
        guard let status else { return "" }
        return """
        <span class="sidebar-run-status" data-testid="sidebar-run-status" title="\(escape(status))" aria-label="\(escape(status))"><span aria-hidden="true">●</span></span>
        """
    }

    private static func renderWorktreeChip(_ worktree: SidebarItemWorktreeSummary?) -> String {
        guard let worktree else { return "" }
        if worktree.location == .local {
            let title = worktree.isResolvable
                ? "Task runs in the local checkout"
                : "Task runs locally; its associated worktree is missing"
            let tone = worktree.isResolvable ? "normal" : "warning"
            return """
            <span class="sidebar-worktree-chip" data-tone="\(tone)" data-testid="sidebar-worktree-local" title="\(escape(title))">Local</span>
            """
        }
        if worktree.isResolvable {
            return """
            <span class="sidebar-worktree-chip" data-testid="sidebar-worktree-branch" title="\(escape(worktree.branch))">⑂ \(escape(worktree.branchLeaf))</span>
            """
        }
        return """
        <span class="sidebar-worktree-warning" data-testid="sidebar-worktree-warning" title="Worktree missing — running in the project root">⚠ Worktree missing</span>
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
