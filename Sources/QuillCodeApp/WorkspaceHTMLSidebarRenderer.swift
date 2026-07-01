enum WorkspaceHTMLSidebarRenderer {
    static func render(
        projects: ProjectListSurface,
        sidebar: SidebarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        """
        <aside class="sidebar" data-testid="sidebar" aria-label="Projects and chats">
          <div class="sidebar-actions" data-testid="sidebar-compose-zone" aria-label="Primary chat actions">
            \(WorkspaceHTMLSidebarCommandRenderer.renderPrimaryActions(commands))
          </div>
          <div class="sidebar-threads-zone" data-testid="sidebar-threads-zone">
            \(WorkspaceHTMLSidebarThreadRenderer.render(sidebar, commands: commands))
          </div>
          \(WorkspaceHTMLSidebarProjectRenderer.render(projects))
          \(WorkspaceHTMLSidebarCommandRenderer.renderFooter(commands))
        </aside>
        """
    }
}
