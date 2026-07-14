import Foundation

enum WorkspaceHTMLSidebarProjectRenderer {
    static func render(_ projects: ProjectListSurface) -> String {
        """
        <div class="sidebar-projects-zone" data-testid="sidebar-projects-zone">
          <div class="sidebar-section-title">
            <h2>\(escape(projects.title))</h2>
            <small data-testid="project-count" aria-label="\(escape(projects.accessibilitySummary))">\(escape(projects.compactCountLabel))</small>
            \(WorkspaceHTMLPrimitives.commandButton(
                "+",
                testID: "add-project-button",
                commandID: "add-project",
                hitTargetKind: .icon,
                ariaLabel: "Open project"
            ))
          </div>
          \(renderProjects(projects))
        </div>
        """
    }

    private static func renderProjects(_ projects: ProjectListSurface) -> String {
        guard !projects.items.isEmpty else {
            return #"<p data-testid="project-empty">\#(escape(projects.emptyTitle))</p>"#
        }

        return projects.items.map(renderProject).joined(separator: "\n")
    }

    private static func renderProject(_ project: ProjectItemSurface) -> String {
        """
        <div class="project-row" data-testid="project-row" data-project-id="\(project.id.uuidString)">
          <button\(WorkspaceHTMLPrimitives.buttonAttributes(
              testID: "project-item",
              hitTargetKind: .row,
              classes: ["project-item", project.isSelected ? "selected" : ""],
              ariaLabel: project.accessibilityLabel,
              title: project.path,
              attributes: [
                  ("data-project-id", project.id.uuidString),
                  ("aria-current", project.isSelected ? "true" : "false")
              ]
          ))>
            <span class="project-title-line"><span class="project-icon" aria-hidden="true">\(project.isRemote ? "⌘" : "▱")</span><span>\(escape(project.name))</span>\(connectionBadge(for: project))</span>
          </button>
          <details class="sidebar-thread-menu" data-testid="project-item-actions">
            \(WorkspaceHTMLPrimitives.summary(
                "•••",
                hitTargetKind: .icon,
                ariaLabel: project.actionMenuAccessibilityLabel,
                title: project.actionMenuHelp
            ))
            <div class="sidebar-thread-menu-popover">
              \(project.actions.map { renderAction($0, projectName: project.name) }.joined(separator: "\n"))
            </div>
          </details>
        </div>
        """
    }

    private static func connectionBadge(for project: ProjectItemSurface) -> String {
        project.isRemote
            ? #" <small class="project-connection-kind" data-testid="project-connection-kind">SSH</small>"#
            : ""
    }

    private static func renderAction(
        _ action: ProjectItemActionSurface,
        projectName: String
    ) -> String {
        WorkspaceHTMLPrimitives.button(
            action.kind.title,
            testID: "project-action",
            hitTargetKind: .row,
            ariaLabel: action.accessibilityLabel(projectName: projectName),
            title: action.helpText(projectName: projectName),
            disabled: !action.isEnabled,
            attributes: [
                ("data-action", action.kind.rawValue),
                ("data-project-id", action.projectID.uuidString)
            ]
        )
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
