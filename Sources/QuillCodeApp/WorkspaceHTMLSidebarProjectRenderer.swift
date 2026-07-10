import Foundation

enum WorkspaceHTMLSidebarProjectRenderer {
    static func render(_ projects: ProjectListSurface) -> String {
        """
        <div class="sidebar-projects-zone" data-testid="sidebar-projects-zone">
          <div class="sidebar-section-title">
            <h2>\(escape(projects.title))</h2>
            <small data-testid="project-count" aria-label="\(escape(projects.accessibilitySummary))">\(escape(projects.countLabel))</small>
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
        <button\(WorkspaceHTMLPrimitives.buttonAttributes(
            testID: "project-item",
            hitTargetKind: .row,
            classes: ["project-item", project.isSelected ? "selected" : ""],
            attributes: [
                ("data-project-id", project.id.uuidString),
                ("aria-current", project.isSelected ? "true" : "false"),
                ("aria-label", project.accessibilityLabel)
            ]
        ))>
          <span>\(escape(project.name))\(selectionBadge(for: project))\(connectionBadge(for: project))</span>
          <small>\(escape(project.path))</small>
        </button>
        """
    }

    private static func selectionBadge(for project: ProjectItemSurface) -> String {
        guard let label = project.selectionLabel else { return "" }
        return #" <small data-testid="project-selection-badge">\#(escape(label))</small>"#
    }

    private static func connectionBadge(for project: ProjectItemSurface) -> String {
        project.isRemote ? #" <small data-testid="project-connection-kind">SSH Remote</small>"# : ""
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
