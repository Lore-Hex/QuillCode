import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section class="quillcode-workspace" data-testid="workspace">
          \(WorkspaceHTMLTopBarRenderer.render(surface.topBar, commands: surface.commands))
          <div class="workspace-grid">
            \(WorkspaceHTMLSidebarRenderer.render(
                projects: surface.projects,
                sidebar: surface.sidebar,
                commands: surface.commands
            ))
            <main class="transcript" data-testid="transcript">
              \(WorkspaceHTMLSecondaryPaneRenderer.renderAutomations(surface.automations))
              \(WorkspaceHTMLTranscriptRenderer.render(
                transcript: surface.transcript,
                contextBanner: surface.contextBanner,
                review: surface.review,
                runtimeIssue: surface.runtimeIssue,
                retryLastTurnCommand: surface.commands.first { $0.id == "retry-last-turn" && $0.isEnabled }
              ))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderExtensions(surface.extensions))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderMemories(surface.memories))
              \(WorkspaceHTMLBrowserRenderer.render(surface.browser))
              \(WorkspaceHTMLTerminalRenderer.render(surface.terminal))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderActivity(surface.activity))
              \(WorkspaceHTMLTranscriptRenderer.renderComposer(surface.composer))
            </main>
          </div>
        </section>
        """
    }
}
