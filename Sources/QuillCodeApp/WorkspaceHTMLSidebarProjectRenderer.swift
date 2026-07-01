enum WorkspaceHTMLSidebarProjectRenderer {
    static func render(_ projects: ProjectListSurface) -> String {
        """
        <div class="sidebar-projects-zone" data-testid="sidebar-projects-zone">
          <div class="sidebar-section-title">
            <h2>\(escape(projects.title))</h2>
            \(WorkspaceHTMLPrimitives.commandButton(
                "+",
                testID: "add-project-button",
                commandID: "add-project",
                hitTargetKind: .icon,
                ariaLabel: "Open project"
            ))
          </div>
          \(renderItems(projects))
        </div>
        """
    }

    private static func renderItems(_ projects: ProjectListSurface) -> String {
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
              <span>\(escape(project.name))\(remoteLabel(for: project))</span>
              <small>\(escape(project.path))</small>
            </button>
            """
        }.joined(separator: "\n")
    }

    private static func remoteLabel(for project: ProjectItemSurface) -> String {
        project.isRemote ? #" <small data-testid="project-connection-kind">SSH Remote</small>"# : ""
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
