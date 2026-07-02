enum WorkspaceHTMLActivityPaneRenderer {
    private typealias Primitives = WorkspaceHTMLSecondaryPanePrimitives

    static func render(_ activity: WorkspaceActivitySurface) -> String {
        guard activity.isVisible else { return "" }
        return """
        <section class="activity-pane" data-testid="activity-pane" aria-label="Task activity">
          <header>
            <div>
              <strong data-testid="activity-title">\(escape(activity.title))</strong>
              <p data-testid="activity-subtitle">\(escape(activity.subtitle))</p>
            </div>
            \(integrityBadgeHTML(activity))<span data-testid="activity-status">\(escape(activity.statusLabel))</span>
          </header>
          <article class="activity-task" data-testid="activity-task">
            <strong data-testid="activity-task-title">\(escape(activity.taskTitle))</strong>
            <p data-testid="activity-task-subtitle">\(escape(activity.taskSubtitle))</p>
          </article>
          \(activity.sections.map(renderActivitySection).joined(separator: "\n"))
        </section>
        """
    }

    /// The run-integrity badge (VERIFIED / UNVERIFIED / RED) rendered as a status pill in the header,
    /// with a `data-integrity` attribute so styling and tests can key off the verdict. Empty until the
    /// run has been scanned.
    private static func integrityBadgeHTML(_ activity: WorkspaceActivitySurface) -> String {
        guard let integrity = activity.integrityBadge else { return "" }
        let detail = activity.integrityDetail.isEmpty ? "" : #" title="\#(escape(activity.integrityDetail))""#
        return #"<span data-testid="activity-integrity" data-integrity="\#(integrity.rawValue)"\#(detail)>\#(escape(integrity.badgeLabel))</span>"#
    }

    private static func renderActivitySection(_ section: ActivitySectionSurface) -> String {
        let content = renderSectionContent(section)
        let collapsed = section.isCollapsed ? "true" : "false"
        let sectionTestID = "\(escape(section.itemTestID))-section"
        return """
        <section class="activity-section" data-testid="\(sectionTestID)" data-collapsed="\(collapsed)">
          <button\(WorkspaceHTMLPrimitives.buttonAttributes(
              testID: "activity-section-toggle",
              hitTargetKind: .row,
              attributes: [
                  ("data-command-id", section.toggleCommandID),
                  ("data-section-title", section.title)
              ]
          ))>
            <span>\(section.isCollapsed ? ">" : "v") \(escape(section.title))</span>
            <span data-testid="activity-section-count">\(escape(section.countLabel))</span>
          </button>
          \(content)
        </section>
        """
    }

    private static func renderSectionContent(_ section: ActivitySectionSurface) -> String {
        if section.isCollapsed {
            return ""
        }
        if let bodyText = section.bodyText {
            return renderBodyText(section: section, bodyText: bodyText)
        }
        if !section.artifacts.isEmpty {
            return section.artifacts.map(renderArtifact(section: section)).joined(separator: "\n")
        }
        if !section.items.isEmpty {
            return section.items.map(renderActivityItem(section: section)).joined(separator: "\n")
        }
        return #"<p data-testid="\#(escape(section.itemTestID))-empty">\#(escape(section.emptyTitle))</p>"#
    }

    private static func renderBodyText(section: ActivitySectionSurface, bodyText: String) -> String {
        """
        <p data-testid="\(escape(section.itemTestID))" style="white-space: pre-wrap;">\(escape(bodyText))</p>
        """
    }

    private static func renderArtifact(section: ActivitySectionSurface) -> (ToolArtifactState) -> String {
        { artifact in
            """
            <article class="activity-artifact" data-testid="\(escape(section.itemTestID))">
              <strong>\(escape(artifact.label))</strong>
              <p>\(escape(artifact.detail))</p>
            </article>
            """
        }
    }

    private static func renderActivityItem(section: ActivitySectionSurface) -> (ActivityItemSurface) -> String {
        { item in
            let actions = renderActivityItemActions(item)
            return """
            <article class="activity-item" data-testid="\(escape(section.itemTestID))" data-kind="\(escape(item.kind))">
              <strong>\(escape(item.title))</strong>
              \(item.statusLabel.isEmpty ? "" : #"<span>\#(escape(item.statusLabel))</span>"#)
              \(item.detail.isEmpty ? "" : #"<p>\#(escape(item.detail))</p>"#)
              \(actions)
            </article>
            """
        }
    }

    private static func renderActivityItemActions(_ item: ActivityItemSurface) -> String {
        guard !item.actions.isEmpty else { return "" }
        let buttons = item.actions.map { action in
            Primitives.commandButton(
                action.title,
                testID: "activity-source-action",
                commandID: action.commandID,
                hitTargetKind: .formAction,
                classes: ["activity-source-action"]
            )
        }.joined(separator: "\n")
        return #"<div class="activity-item-actions">\#(buttons)</div>"#
    }

    private static func escape(_ text: String) -> String {
        Primitives.escape(text)
    }
}
