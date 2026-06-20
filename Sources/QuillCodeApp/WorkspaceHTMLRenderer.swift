import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section class="quillcode-workspace" data-testid="workspace">
          \(renderTopBar(surface.topBar))
          <div class="workspace-grid">
            \(renderSidebar(projects: surface.projects, sidebar: surface.sidebar))
            <main class="transcript" data-testid="transcript">
              \(renderTranscript(surface.transcript, review: surface.review))
              \(renderTerminal(surface.terminal))
              \(renderComposer(surface.composer))
            </main>
          </div>
        </section>
        """
    }

    private static func renderTopBar(_ topBar: TopBarSurface) -> String {
        """
        <header class="topbar" data-testid="top-bar" aria-label="QuillCode top bar">
          <div>
            <strong data-testid="top-bar-title">\(escape(topBar.primaryTitle))</strong>
            <p data-testid="top-bar-subtitle">\(escape(topBar.subtitle))</p>
          </div>
          <div class="topbar-pills">
            <span data-testid="model-pill">\(escape(topBar.modelLabel))</span>
            <span data-testid="mode-pill">\(escape(topBar.modeLabel))</span>
            <span data-testid="agent-status">\(escape(topBar.agentStatus))</span>
            <span data-testid="computer-use-status">\(escape(topBar.computerUseLabel))</span>
          </div>
        </header>
        """
    }

    private static func renderSidebar(projects: ProjectListSurface, sidebar: SidebarSurface) -> String {
        let projectContent: String
        if projects.items.isEmpty {
            projectContent = #"<p data-testid="project-empty">\#(escape(projects.emptyTitle))</p>"#
        } else {
            projectContent = projects.items.map { project in
                """
                <button class="project-item\(project.isSelected ? " selected" : "")" data-testid="project-item" data-project-id="\(project.id.uuidString)" aria-current="\(project.isSelected ? "true" : "false")">
                  <span>\(escape(project.name))</span>
                  <small>\(escape(project.path))</small>
                </button>
                """
            }.joined(separator: "\n")
        }

        let content: String
        if sidebar.items.isEmpty {
            content = #"<p data-testid="sidebar-empty">\#(escape(sidebar.emptyTitle))</p>"#
        } else {
            content = sidebar.items.map { item in
                """
                <button class="sidebar-item\(item.isSelected ? " selected" : "")" data-testid="sidebar-item" data-thread-id="\(item.id.uuidString)" aria-current="\(item.isSelected ? "true" : "false")">
                  <span>\(escape(item.title))</span>
                  <small>\(escape(item.subtitle))\(item.isPinned ? " · pinned" : "")</small>
                </button>
                """
            }.joined(separator: "\n")
        }
        return """
        <aside class="sidebar" data-testid="sidebar" aria-label="Projects and chats">
          <h2>\(escape(projects.title))</h2>
          \(projectContent)
          <h2>\(escape(sidebar.title))</h2>
          \(content)
        </aside>
        """
    }

    private static func renderTranscript(_ transcript: TranscriptSurface, review: WorkspaceReviewSurface) -> String {
        let reviewPane = renderReview(review)
        let messages = transcript.messages.map { message in
            """
            <article class="message \(message.role.rawValue)" data-testid="message" aria-label="\(escape(message.accessibilityLabel))">
              \(escape(message.text))
            </article>
            """
        }.joined(separator: "\n")
        let cards = transcript.toolCards.map(renderToolCard).joined(separator: "\n")
        if messages.isEmpty && cards.isEmpty && !review.isVisible {
            return """
            <section class="empty" data-testid="transcript-empty">
              <h1>\(escape(transcript.emptyTitle))</h1>
              <p>\(escape(transcript.emptySubtitle))</p>
            </section>
            """
        }
        return reviewPane + "\n" + messages + "\n" + cards
    }

    private static func renderReview(_ review: WorkspaceReviewSurface) -> String {
        guard review.isVisible else { return "" }
        let files = review.files.map { file in
            """
            <li data-testid="review-file">
              <span data-testid="review-file-path">\(escape(file.path))</span>
              <small>\(escape(file.changeLabel))</small>
              <span>
                \(file.actions.map(renderReviewAction).joined(separator: "\n"))
              </span>
              \(file.hunkItems.map(renderReviewHunk).joined(separator: "\n"))
            </li>
            """
        }.joined(separator: "\n")
        return """
        <section class="review-pane" data-testid="review-pane" aria-label="Git review summary">
          <header>
            <strong>\(escape(review.title))</strong>
            <span data-testid="review-summary">\(escape(review.subtitle))</span>
          </header>
          <ul>
            \(files)
          </ul>
        </section>
        """
    }

    private static func renderReviewHunk(_ hunk: WorkspaceReviewHunkSurface) -> String {
        """
        <div data-testid="review-hunk">
          <code data-testid="review-hunk-header">\(escape(hunk.header))</code>
          <small>\(escape(hunk.changeLabel))</small>
          <span>
            \(hunk.actions.map(renderReviewAction).joined(separator: "\n"))
          </span>
        </div>
        """
    }

    private static func renderReviewAction(_ action: WorkspaceReviewActionSurface) -> String {
        """
        <button type="button" data-testid="review-action" data-action="\(escape(action.kind.rawValue))" data-path="\(escape(action.path))">\(escape(action.kind.title))</button>
        """
    }

    private static func renderToolCard(_ card: ToolCardState) -> String {
        """
        <article class="tool-card \(card.status.rawValue)" data-testid="tool-card" data-status="\(card.status.rawValue)">
          <header>
            <strong data-testid="tool-card-title">\(escape(card.title))</strong>
            <span data-testid="tool-card-status">\(escape(card.status.rawValue))</span>
          </header>
          <p>\(escape(card.subtitle))</p>
          \(card.inputJSON.map { #"<pre data-testid="tool-card-input">\#(escape($0))</pre>"# } ?? "")
          \(card.outputJSON.map { #"<pre data-testid="tool-card-output">\#(escape($0))</pre>"# } ?? "")
        </article>
        """
    }

    private static func renderTerminal(_ terminal: TerminalSurface) -> String {
        guard terminal.isVisible else { return "" }
        let entries = terminal.entries.isEmpty
            ? #"<p data-testid="terminal-empty">\#(escape(terminal.emptyTitle))</p>"#
            : terminal.entries.map { entry in
                """
                <article class="terminal-entry" data-testid="terminal-entry">
                  <header>
                    <code>$ \(escape(entry.command))</code>
                    <span data-testid="terminal-status">\(escape(entry.statusLabel)) · \(escape(entry.exitCodeLabel))</span>
                  </header>
                  \(entry.stdout.isEmpty ? "" : #"<pre data-testid="terminal-stdout">\#(escape(entry.stdout))</pre>"#)
                  \(entry.stderr.isEmpty ? "" : #"<pre data-testid="terminal-stderr">\#(escape(entry.stderr))</pre>"#)
                </article>
                """
            }.joined(separator: "\n")
        return """
        <section class="terminal-pane" data-testid="terminal-pane">
          <header>
            <strong>Terminal</strong>
            <code data-testid="terminal-cwd">\(escape(terminal.cwdLabel))</code>
          </header>
          <div data-testid="terminal-history">
            \(entries)
          </div>
          <form data-testid="terminal-form">
            <input aria-label="Terminal command" value="\(escape(terminal.draft))">
            <button type="submit" data-testid="terminal-run" \(terminal.canRun ? "" : "disabled")>Run</button>
          </form>
        </section>
        """
    }

    private static func renderComposer(_ composer: ComposerSurface) -> String {
        """
        <form class="composer" data-testid="composer">
          <label for="message">Message</label>
          <input id="message" aria-label="Message" placeholder="\(escape(composer.placeholder))" value="\(escape(composer.draft))" \(composer.isSending ? "disabled" : "")>
          <button type="submit" data-testid="send-button" \(composer.canSend ? "" : "disabled")>Send</button>
        </form>
        """
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
