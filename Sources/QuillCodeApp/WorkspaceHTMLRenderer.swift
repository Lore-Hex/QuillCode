import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section class="quillcode-workspace" data-testid="workspace">
          \(renderTopBar(surface.topBar))
          <div class="workspace-grid">
            \(renderSidebar(projects: surface.projects, sidebar: surface.sidebar))
            <main class="transcript" data-testid="transcript">
              \(renderTranscript(surface.transcript, contextBanner: surface.contextBanner, review: surface.review))
              \(renderBrowser(surface.browser))
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
            <span data-testid="project-instructions-status" title="\(escape(topBar.instructionSources.joined(separator: ", ")))">\(escape(topBar.instructionLabel))</span>
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
            content = [
                renderSidebarSection(title: "Pinned", items: sidebar.pinnedItems),
                renderSidebarSection(title: "Recent", items: sidebar.recentItems)
            ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }
        return """
        <aside class="sidebar" data-testid="sidebar" aria-label="Projects and chats">
          <div class="sidebar-section-title">
            <h2>\(escape(projects.title))</h2>
            <button type="button" data-testid="add-project-button" aria-label="Open project">+</button>
          </div>
          \(projectContent)
          <h2>\(escape(sidebar.title))</h2>
          \(content)
        </aside>
        """
    }

    private static func renderSidebarSection(title: String, items: [SidebarItemSurface]) -> String {
        guard !items.isEmpty else { return "" }
        let rows = items.map { item in
            """
            <div data-testid="sidebar-thread-row">
              <button class="sidebar-item\(item.isSelected ? " selected" : "")" data-testid="sidebar-item" data-thread-id="\(item.id.uuidString)" aria-current="\(item.isSelected ? "true" : "false")">
                <span>\(escape(item.title))</span>
                <small>\(escape(item.subtitle))</small>
              </button>
              <span data-testid="sidebar-item-actions">
                \(item.actions.map(renderSidebarAction).joined(separator: "\n"))
              </span>
            </div>
            """
        }.joined(separator: "\n")
        return """
        <section data-testid="sidebar-section">
          <h3 data-testid="sidebar-section-title">\(escape(title))</h3>
          \(rows)
        </section>
        """
    }

    private static func renderSidebarAction(_ action: SidebarItemActionSurface) -> String {
        """
        <button type="button" data-testid="sidebar-thread-action" data-action="\(escape(action.kind.rawValue))" data-thread-id="\(action.threadID.uuidString)">\(escape(action.kind.title))</button>
        """
    }

    private static func renderTranscript(
        _ transcript: TranscriptSurface,
        contextBanner: ContextBannerSurface?,
        review: WorkspaceReviewSurface
    ) -> String {
        let context = renderContextBanner(contextBanner)
        let reviewPane = renderReview(review)
        let timeline = transcript.timelineItems.map(renderTimelineItem).joined(separator: "\n")
        if context.isEmpty && timeline.isEmpty && !review.isVisible {
            return """
            <section class="empty" data-testid="transcript-empty">
              <h1>\(escape(transcript.emptyTitle))</h1>
              <p>\(escape(transcript.emptySubtitle))</p>
            </section>
            """
        }
        return context + "\n" + reviewPane + "\n" + timeline
    }

    private static func renderTimelineItem(_ item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            guard let message = item.message else { return "" }
            return """
            <article class="message \(message.role.rawValue)" data-testid="message" aria-label="\(escape(message.accessibilityLabel))">
              \(escape(message.text))
            </article>
            """
        case .toolCard:
            guard let card = item.toolCard else { return "" }
            return renderToolCard(card)
        }
    }

    private static func renderContextBanner(_ banner: ContextBannerSurface?) -> String {
        guard let banner else { return "" }
        return """
        <section class="context-banner" data-testid="context-banner" aria-label="Context limit warning">
          <header>
            <strong data-testid="context-banner-title">\(escape(banner.title))</strong>
            <span data-testid="context-banner-percent">\(banner.usedPercent)%</span>
          </header>
          <p data-testid="context-banner-subtitle">\(escape(banner.subtitle))</p>
          <div>
            <button type="button" data-testid="context-new-thread" data-command-id="\(escape(banner.newThreadCommand.id))">\(escape(banner.newThreadCommand.title))</button>
            <button type="button" data-testid="context-fork-last" data-command-id="\(escape(banner.forkCommand.id))">\(escape(banner.forkCommand.title))</button>
          </div>
        </section>
        """
    }

    private static func renderReview(_ review: WorkspaceReviewSurface) -> String {
        guard review.isVisible else { return "" }
        let files = review.files.map { file in
            let comments = file.comments.map { comment in
                """
                <blockquote data-testid="review-comment">\(escape(comment.text))</blockquote>
                """
            }.joined(separator: "\n")
            return """
            <li data-testid="review-file">
              <span data-testid="review-file-path">\(escape(file.path))</span>
              <small>\(escape(file.changeLabel))</small>
              <span>
                \(file.actions.map(renderReviewAction).joined(separator: "\n"))
              </span>
              \(file.hunkItems.map(renderReviewHunk).joined(separator: "\n"))
              \(comments)
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
          <ol data-testid="review-lines">
            \(hunk.lines.map(renderReviewLine).joined(separator: "\n"))
          </ol>
        </div>
        """
    }

    private static func renderReviewLine(_ line: WorkspaceReviewLineSurface) -> String {
        let comments = line.comments.map { comment in
            """
            <blockquote data-testid="review-line-comment">\(comment.lineRangeLabel.map { "<strong>\(escape($0))</strong> " } ?? "")\(escape(comment.text))</blockquote>
            """
        }.joined(separator: "\n")
        return """
        <li data-testid="review-line" data-line-kind="\(escape(line.kind.rawValue))">
          <span data-testid="review-line-number">\(escape(line.lineLabel))</span>
          <span data-testid="review-line-marker">\(escape(line.kind.marker))</span>
          <code data-testid="review-line-content">\(escape(line.content))</code>
          \(comments)
        </li>
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
          \(renderToolArtifacts(card.artifacts))
          \(card.inputJSON.map { #"<pre data-testid="tool-card-input">\#(escape($0))</pre>"# } ?? "")
          \(card.outputJSON.map { #"<pre data-testid="tool-card-output">\#(escape($0))</pre>"# } ?? "")
        </article>
        """
    }

    private static func renderToolArtifacts(_ artifacts: [ToolArtifactState]) -> String {
        guard !artifacts.isEmpty else { return "" }
        let chips = artifacts.map { artifact in
            let href = artifactHref(artifact).map { #" href="\#(escape($0))""# } ?? ""
            return """
            <a class="artifact-chip" data-testid="tool-card-artifact" data-kind="\(escape(artifact.kind.rawValue))"\(href)>\(escape(artifact.label))</a>
            """
        }.joined(separator: "\n")
        return """
        <div class="tool-artifacts" data-testid="tool-card-artifacts" aria-label="Artifacts">
          \(chips)
        </div>
        """
    }

    private static func artifactHref(_ artifact: ToolArtifactState) -> String? {
        switch artifact.kind {
        case .url:
            return artifact.value
        case .file:
            if artifact.value.hasPrefix("file://") {
                return artifact.value
            }
            if artifact.value.hasPrefix("/") {
                return URL(fileURLWithPath: artifact.value).absoluteString
            }
            return nil
        case .path:
            return nil
        }
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

    private static func renderBrowser(_ browser: BrowserSurface) -> String {
        guard browser.isVisible else { return "" }
        let preview: String
        if let currentURL = browser.currentURL {
            preview = """
            <div class="browser-preview" data-testid="browser-preview">
              <strong data-testid="browser-title">\(escape(browser.title))</strong>
              <code data-testid="browser-current-url">\(escape(currentURL))</code>
              <p data-testid="browser-status">\(escape(browser.statusLabel))</p>
            </div>
            """
        } else {
            preview = """
            <div class="browser-preview empty" data-testid="browser-empty">
              <strong>\(escape(browser.emptyTitle))</strong>
              <p>\(escape(browser.emptySubtitle))</p>
            </div>
            """
        }
        let comments = browser.comments.map { comment in
            """
            <article data-testid="browser-comment">
              <p>\(escape(comment.text))</p>
              <small>\(escape(comment.url))</small>
            </article>
            """
        }.joined(separator: "\n")
        return """
        <section class="browser-pane" data-testid="browser-pane">
          <header>
            <strong>Browser</strong>
            <span data-testid="browser-status-label">\(escape(browser.statusLabel))</span>
          </header>
          <form data-testid="browser-form">
            <input aria-label="Browser address" value="\(escape(browser.addressDraft))">
            <button type="submit" data-testid="browser-open" \(browser.canOpen ? "" : "disabled")>Open</button>
          </form>
          \(preview)
          <form data-testid="browser-comment-form">
            <input aria-label="Browser comment" placeholder="Add browser comment">
            <button type="submit" data-testid="browser-add-comment" \(browser.currentURL == nil ? "disabled" : "")>Comment</button>
          </form>
          <div data-testid="browser-comments">
            \(comments)
          </div>
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
