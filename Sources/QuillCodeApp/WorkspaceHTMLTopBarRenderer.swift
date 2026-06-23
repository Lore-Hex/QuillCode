import Foundation

enum WorkspaceHTMLTopBarRenderer {
    static func render(_ topBar: TopBarSurface, commands: [WorkspaceCommandSurface]) -> String {
        """
        <header class="topbar" data-testid="top-bar" aria-label="QuillCode top bar">
          <div class="topbar-title-group" data-testid="top-bar-title-group">
            <span>
              <strong data-testid="top-bar-title">\(escape(topBar.primaryTitle))</strong>
              <p data-testid="top-bar-subtitle">\(escape(topBar.subtitle))</p>
            </span>
          </div>
          <div class="topbar-clusters" data-testid="top-bar-clusters">
            \(renderStatusCluster(topBar))
            \(renderActionCluster(topBar, commands: commands))
          </div>
        </header>
        """
    }

    private static func renderStatusCluster(_ topBar: TopBarSurface) -> String {
        let status = topBar.agentStatusPresentation
        return """
        <div class="topbar-cluster topbar-context-cluster" data-testid="top-bar-context-cluster" aria-label="Workspace state">
          <details class="topbar-status-menu" data-testid="top-bar-status-menu">
            <summary data-testid="top-bar-status-button" aria-label="Workspace status" title="\(escape(status.label))">
              <span class="agent-status-dot" data-testid="agent-status" data-tone="\(escape(status.tone.rawValue))" data-indicator="\(status.showsIndicator)">\(escape(status.label))</span>
            </summary>
            <div class="topbar-status-popover" data-testid="top-bar-status-popover">
              <div class="topbar-status-row">
                <span>Status</span>
                <strong>\(escape(status.label))</strong>
              </div>
              \(renderRuntimeIssuePill(topBar))
              <div class="topbar-status-row">
                <span>Instructions</span>
                <strong data-testid="project-instructions-status" title="\(escape(topBar.instructionSources.joined(separator: ", ")))">\(escape(topBar.instructionLabel))</strong>
              </div>
              <div class="topbar-status-row">
                <span>Memories</span>
                <strong data-testid="project-memories-status" title="\(escape(topBar.memorySources.joined(separator: ", ")))">\(escape(topBar.memoryLabel))</strong>
              </div>
              <div class="topbar-status-row">
                <span>Computer Use</span>
                <strong data-testid="computer-use-status">\(escape(topBar.computerUseLabel))</strong>
              </div>
            </div>
          </details>
        </div>
        """
    }

    private static func renderRuntimeIssuePill(_ topBar: TopBarSurface) -> String {
        guard let issue = topBar.runtimeIssuePresentation else { return "" }
        return #"<span data-testid="runtime-issue-pill" data-severity="\#(escape(issue.tone.rawValue))">\#(escape(issue.label))</span>"#
    }

    private static func renderActionCluster(
        _ topBar: TopBarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
        """
        <div class="topbar-cluster topbar-action-cluster" data-testid="top-bar-action-cluster">
          <details class="topbar-overflow-menu" data-testid="top-bar-overflow-menu">
            <summary data-testid="top-bar-overflow-button" aria-label="More" title="More">...</summary>
            <div class="topbar-overflow-popover">
              \(renderOverflow(commands: commands, showsComputerUseSetup: topBar.showsComputerUseSetup))
            </div>
          </details>
        </div>
        """
    }

    private static func renderOverflow(
        commands: [WorkspaceCommandSurface],
        showsComputerUseSetup: Bool
    ) -> String {
        TopBarOverflowCommandCatalog.commands(
            from: commands,
            showsComputerUseSetup: showsComputerUseSetup
        )
        .map(renderOverflowButton)
        .joined(separator: "\n")
    }

    private static func renderOverflowButton(_ command: WorkspaceCommandSurface) -> String {
        let testID = TopBarOverflowCommandCatalog.testID(for: command.id)
        let disabledAttribute = command.isEnabled ? "" : #" disabled aria-disabled="true""#
        let title = command.shortcut.map { "\(command.title) (\($0))" } ?? command.title
        return #"<button type="button" data-testid="\#(escape(testID))" data-command-id="\#(escape(command.id))" title="\#(escape(title))"\#(disabledAttribute)>\#(escape(command.title))</button>"#
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
