import Foundation
import QuillCodeCore

enum WorkspaceHTMLSidebarThreadRenderer {
    static func render(_ sidebar: SidebarSurface, commands: [WorkspaceCommandSurface]) -> String {
        """
        <div class="sidebar-threads-zone" data-testid="sidebar-threads-zone">
          \(renderThreadHeader(sidebar, commands: commands))
          \(renderBulkToolbar(sidebar))
          \(renderThreadSections(sidebar))
        </div>
        """
    }

    private static func renderThreadHeader(
        _ sidebar: SidebarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        guard !sidebar.items.isEmpty || sidebar.isSelectionMode else { return "" }
        return """
        <div class="sidebar-title-row" data-testid="sidebar-title-row">
          <h2>\(escape(sidebar.title))</h2>
          <span class="sidebar-title-actions">
            \(renderSelectionHeaderAction(sidebar))
            \(renderFilterMenu(sidebar, commands: commands))
          </span>
        </div>
        """
    }

    private static func renderFilterMenu(
        _ sidebar: SidebarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        let filters = sidebar.savedFilters.map(renderSavedFilter).joined(separator: "\n")
        let activeSavedSearch = sidebar.customSavedSearches.first(where: \.isActive)
        let activeFilter = sidebar.savedFilters.first(where: \.isActive)
        let activeTitle = activeSavedSearch?.title ?? activeFilter?.title ?? "Custom"
        let activeCount = activeSavedSearch?.count ?? activeFilter?.count ?? 0
        let isRefined = activeSavedSearch != nil || activeFilter?.kind != .all
        return """
        <details class="sidebar-filter-menu" data-testid="sidebar-filter-menu" data-active="\(isRefined)">
          \(WorkspaceHTMLPrimitives.summary(
              "Filter",
              testID: "sidebar-filter-menu-button",
              hitTargetKind: .icon,
              ariaLabel: "Filter chats, \(activeTitle), \(activeCount)",
              title: "Filter chats"
          ))
          <div class="sidebar-filter-popover" role="menu">
            <section class="sidebar-filter-section">
              <h3>Chats</h3>
              \(filters)
            </section>
            \(WorkspaceHTMLSidebarSavedSearchRenderer.render(sidebar, commands: commands))
            \(renderSelectionMenuAction(sidebar))
          </div>
        </details>
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
        let toolbarActions = sidebar.bulkActions.filter { $0.kind != .clearSelection }
        guard sidebar.isSelectionMode, !toolbarActions.isEmpty else { return "" }
        let actions = toolbarActions.map(renderBulkAction).joined(separator: "\n")
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
              ariaLabel: "\(item.title), \(item.subtitle), updated \(activityLabel(for: item))",
              title: item.subtitle,
              attributes: [
                  ("data-thread-id", item.id.uuidString),
                  ("aria-current", item.isSelected ? "true" : "false"),
                  ("data-run-status", item.runStatusLabel ?? "")
              ]
          ))>
            <span class="sidebar-title-line"><span>\(escape(item.title))</span>\(renderRunStatus(item.runStatusLabel))<time data-testid="sidebar-activity">\(escape(activityLabel(for: item)))</time></span>
            <span class="sidebar-thread-metadata">\(renderWorktreeChip(item.worktree))\(renderPullRequestChip(item.pullRequest))</span>
          </button>
          <details class="sidebar-thread-menu" data-testid="sidebar-item-actions">
            \(WorkspaceHTMLPrimitives.summary(
                "•••",
                hitTargetKind: .icon,
                ariaLabel: "Thread actions for \(item.title)",
                title: "Thread actions"
            ))
            <div class="sidebar-thread-menu-popover">
              \(item.actions.map(renderAction).joined(separator: "\n"))
            </div>
          </details>
        </div>
        """
    }

    private static func renderRunStatus(_ status: String?) -> String {
        guard let status else { return "" }
        return """
        <span class="sidebar-run-status" data-testid="sidebar-run-status" title="\(escape(status))" aria-label="\(escape(status))"><span aria-hidden="true">●</span></span>
        """
    }

    private static func activityLabel(for item: SidebarItemSurface) -> String {
        SidebarActivityLabelFormatter.label(for: item.updatedAt)
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
        if worktree.hasRestorableSnapshot {
            return """
            <span class="sidebar-worktree-chip" data-testid="sidebar-worktree-snapshot" title="Managed worktree saved and ready to restore">↻ Worktree saved</span>
            """
        }
        return """
        <span class="sidebar-worktree-warning" data-testid="sidebar-worktree-warning" title="Worktree missing — running in the project root">⚠ Worktree missing</span>
        """
    }

    private static func renderPullRequestChip(_ pullRequest: PullRequestLink?) -> String {
        guard let pullRequest else { return "" }
        return """
        <span class="sidebar-pr-chip" data-testid="sidebar-pr-status" data-tone="\(escape(pullRequest.status.rawValue))" title="\(escape(pullRequest.title))">\(escape(pullRequest.compactLabel))</span>
        """
    }

    private static func renderSelectionHeaderAction(_ sidebar: SidebarSurface) -> String {
        guard sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .clearSelection })
        else { return "" }
        return renderBulkAction(action)
    }

    private static func renderSelectionMenuAction(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .select })
        else { return "" }
        let selectAction = WorkspaceHTMLPrimitives.commandButton(
            "Select chats",
            testID: "sidebar-select-chats",
            commandID: action.commandID,
            hitTargetKind: .text,
            disabled: !action.isEnabled,
            attributes: [
                ("data-action", action.kind.rawValue),
                ("data-destructive", String(action.isDestructive))
            ]
        )
        return """
        <section class="sidebar-filter-section">
          <h3>Actions</h3>
          \(selectAction)
        </section>
        """
    }

    private static func renderAction(_ action: SidebarItemActionSurface) -> String {
        WorkspaceHTMLPrimitives.button(
            action.kind.title,
            testID: "sidebar-thread-action",
            hitTargetKind: .row,
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
