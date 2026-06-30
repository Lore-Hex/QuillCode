import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section \(workspaceAttributes(for: surface.chrome))>
          \(WorkspaceHTMLTopBarRenderer.render(surface.topBar, commands: surface.commands))
          <div class="\(workspaceGridClass(for: surface))">
            \(sidebarHTML(for: surface))
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
              \(WorkspaceHTMLTranscriptRenderer.renderComposer(surface.composer, topBar: surface.topBar))
            </main>
          </div>
        </section>
        """
    }

    private static func workspaceAttributes(for chrome: WorkspaceChromeSurface) -> String {
        #"class="quillcode-workspace" data-testid="workspace" data-sidebar-visible="\#(chrome.isSidebarVisible)""#
    }

    private static func workspaceGridClass(for surface: WorkspaceSurface) -> String {
        [
            "workspace-grid",
            surface.chrome.isSidebarVisible ? nil : "sidebar-hidden",
            surface.activity.isVisible ? "with-activity" : nil
        ]
        .compactMap(\.self)
        .joined(separator: " ")
    }

    private static func sidebarHTML(for surface: WorkspaceSurface) -> String {
        guard surface.chrome.isSidebarVisible else { return "" }
        return WorkspaceHTMLSidebarRenderer.render(
            projects: surface.projects,
            sidebar: surface.sidebar,
            commands: surface.commands
        )
    }
}
