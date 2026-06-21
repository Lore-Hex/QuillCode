import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section class="quillcode-workspace" data-testid="workspace">
          \(renderTopBar(surface.topBar))
          <div class="workspace-grid">
            \(renderSidebar(projects: surface.projects, sidebar: surface.sidebar))
            <main class="transcript" data-testid="transcript">
              \(renderTranscript(surface.transcript, contextBanner: surface.contextBanner, review: surface.review, runtimeIssue: surface.runtimeIssue))
              \(renderExtensions(surface.extensions))
              \(renderMemories(surface.memories))
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
            <span data-testid="project-memories-status" title="\(escape(topBar.memorySources.joined(separator: ", ")))">\(escape(topBar.memoryLabel))</span>
            <span data-testid="agent-status">\(escape(topBar.agentStatus))</span>
            \(topBar.runtimeIssueLabel.map { #"<span data-testid="runtime-issue-pill" data-severity="\#(escape(topBar.runtimeIssueSeverity?.rawValue ?? "warning"))">\#(escape($0))</span>"# } ?? "")
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
                renderSidebarSection(title: "Recent", items: sidebar.recentItems),
                renderSidebarSection(title: "Archived", items: sidebar.archivedItems)
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
        review: WorkspaceReviewSurface,
        runtimeIssue: RuntimeIssueSurface? = nil
    ) -> String {
        let context = renderContextBanner(contextBanner)
        let issue = renderRuntimeIssue(runtimeIssue)
        let reviewPane = renderReview(review)
        let timeline = transcript.timelineItems.map(renderTimelineItem).joined(separator: "\n")
        if context.isEmpty && issue.isEmpty && timeline.isEmpty && !review.isVisible {
            return """
            <section class="empty" data-testid="transcript-empty">
              <h1>\(escape(transcript.emptyTitle))</h1>
              <p>\(escape(transcript.emptySubtitle))</p>
            </section>
            """
        }
        return context + "\n" + issue + "\n" + reviewPane + "\n" + timeline
    }

    private static func renderRuntimeIssue(_ issue: RuntimeIssueSurface?) -> String {
        guard let issue else { return "" }
        let diagnostics = issue.diagnostics.isEmpty ? "" : """
          <dl class="runtime-diagnostics" data-testid="runtime-diagnostics">
            \(issue.diagnostics.map { diagnostic in
              #"<div data-testid="runtime-diagnostic"><dt data-testid="runtime-diagnostic-label">\#(escape(diagnostic.label))</dt><dd data-testid="runtime-diagnostic-value">\#(escape(diagnostic.value))</dd></div>"#
            }.joined(separator: "\n"))
          </dl>
        """
        return """
        <section class="runtime-issue \(escape(issue.severity.rawValue))" data-testid="runtime-issue" data-severity="\(escape(issue.severity.rawValue))" aria-label="Runtime issue">
          <header>
            <strong data-testid="runtime-issue-title">\(escape(issue.title))</strong>
            <span data-testid="runtime-issue-severity">\(escape(issue.severity.rawValue))</span>
          </header>
          <p data-testid="runtime-issue-message">\(escape(issue.message))</p>
          \(issue.actionLabel.map { #"<button type="button" data-testid="runtime-issue-action">\#(escape($0))</button>"# } ?? "")
          \(diagnostics)
        </section>
        """
    }

    private static func renderTimelineItem(_ item: TranscriptTimelineItemSurface) -> String {
        switch item.kind {
        case .message:
            guard let message = item.message else { return "" }
            return """
            <article class="message \(message.role.rawValue)" data-testid="message" data-timeline-id="\(escape(item.id))" aria-label="\(escape(message.accessibilityLabel))">
              <p>\(escape(message.text))</p>
              <footer class="transcript-actions">
                <button type="button" data-testid="message-copy" data-copy-id="\(escape(item.id))">Copy</button>
                \(renderMessageFeedbackActions(message))
              </footer>
            </article>
            """
        case .toolCard:
            guard let card = item.toolCard else { return "" }
            return renderToolCard(card, timelineItemID: item.id)
        }
    }

    private static func renderMessageFeedbackActions(_ message: MessageSurface) -> String {
        guard message.role == .assistant else { return "" }
        let helpfulSelected = message.feedback == .helpful ? "true" : "false"
        let notHelpfulSelected = message.feedback == .notHelpful ? "true" : "false"
        return """
        <button type="button" data-testid="message-feedback-up" data-message-id="\(message.id.uuidString)" data-selected="\(helpfulSelected)">Helpful</button>
        <button type="button" data-testid="message-feedback-down" data-message-id="\(message.id.uuidString)" data-selected="\(notHelpfulSelected)">Not helpful</button>
        """
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
            <button type="button" data-testid="context-compact" data-command-id="\(escape(banner.compactCommand.id))">\(escape(banner.compactCommand.title))</button>
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

    private static func renderToolCard(_ card: ToolCardState, timelineItemID: String? = nil) -> String {
        let timelineAttribute = timelineItemID.map { #" data-timeline-id="\#(escape($0))""# } ?? ""
        let copyID = timelineItemID ?? card.id
        return """
        <article class="tool-card \(card.status.rawValue)" data-testid="tool-card" data-status="\(card.status.rawValue)"\(timelineAttribute)>
          <header>
            <strong data-testid="tool-card-title">\(escape(card.title))</strong>
            <span data-testid="tool-card-status">\(escape(card.status.rawValue))</span>
          </header>
          <p>\(escape(card.subtitle))</p>
          <footer class="transcript-actions">
            <button type="button" data-testid="tool-card-copy" data-copy-id="\(escape(copyID))">\(escape(copyActionLabel(for: card)))</button>
          </footer>
          \(renderToolArtifacts(card.artifacts))
          \(renderToolDetails(card))
        </article>
        """
    }

    private static func copyActionLabel(for card: ToolCardState) -> String {
        if card.outputJSON != nil {
            return "Copy output"
        }
        if card.inputJSON != nil {
            return "Copy input"
        }
        return "Copy"
    }

    private static func renderToolDetails(_ card: ToolCardState) -> String {
        guard card.inputJSON != nil || card.outputJSON != nil else { return "" }
        let isOpen = card.isExpanded || card.status == .failed || card.status == .review
        return """
        <details data-testid="tool-card-details"\(isOpen ? " open" : "")>
          <summary>\(isOpen ? "Hide details" : "Show details")</summary>
          \(card.inputJSON.map { #"<pre data-testid="tool-card-input">\#(escape($0))</pre>"# } ?? "")
          \(card.outputJSON.map { #"<pre data-testid="tool-card-output">\#(escape($0))</pre>"# } ?? "")
        </details>
        """
    }

    private static func renderToolArtifacts(_ artifacts: [ToolArtifactState]) -> String {
        guard !artifacts.isEmpty else { return "" }
        let chips = artifacts.map { artifact in
            let href = artifactHref(artifact).map { #" href="\#(escape($0))""# } ?? ""
            return """
            <a class="artifact-chip" data-testid="tool-card-artifact" data-kind="\(escape(artifact.kind.rawValue))"\(href)>
              <strong data-testid="tool-card-artifact-label">\(escape(artifact.label))</strong>
              <small data-testid="tool-card-artifact-detail">\(escape(artifact.detail))</small>
            </a>
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
        let snapshot = browser.snapshot.map { snapshot in
            """
            <div class="browser-snapshot" data-testid="browser-snapshot">
              <span data-testid="browser-source">\(escape(snapshot.sourceLabel))</span>
              <p data-testid="browser-snapshot-summary">\(escape(snapshot.summary))</p>
              <ul>
                \(snapshot.details.map { #"<li data-testid="browser-snapshot-detail">\#(escape($0))</li>"# }.joined(separator: "\n"))
              </ul>
            </div>
            """
        } ?? ""
        let preview: String
        if let currentURL = browser.currentURL {
            preview = """
            <div class="browser-preview" data-testid="browser-preview">
              <strong data-testid="browser-title">\(escape(browser.title))</strong>
              <code data-testid="browser-current-url">\(escape(currentURL))</code>
              \(snapshot)
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

    private static func renderExtensions(_ extensions: WorkspaceExtensionsSurface) -> String {
        guard extensions.isVisible else { return "" }
        let counts = """
        <span data-testid="extensions-count">\(countLabel(extensions.pluginCount, singular: "plugin"))</span>
        <span data-testid="extensions-count">\(countLabel(extensions.skillCount, singular: "skill"))</span>
        <span data-testid="extensions-count">\(countLabel(extensions.mcpServerCount, singular: "MCP server"))</span>
        """
        let content: String
        if extensions.items.isEmpty {
            content = """
            <div class="extensions-empty" data-testid="extensions-empty">
              <strong>\(escape(extensions.emptyTitle))</strong>
              <p>\(escape(extensions.emptySubtitle))</p>
            </div>
            """
        } else {
            content = """
            <div class="extensions-grid" data-testid="extensions-grid">
              \(extensions.items.map(renderExtensionItem).joined(separator: "\n"))
            </div>
            """
        }
        return """
        <section class="extensions-pane" data-testid="extensions-pane" aria-label="Project extensions">
          <header>
            <div>
              <strong>\(escape(extensions.title))</strong>
              <p data-testid="extensions-subtitle">\(escape(extensions.subtitle))</p>
            </div>
            <span class="extensions-counts">
              \(counts)
            </span>
          </header>
          \(content)
        </section>
        """
    }

    private static func renderExtensionItem(_ item: ProjectExtensionManifestSurface) -> String {
        """
        <article class="extension-card" data-testid="extension-item" data-kind="\(escape(item.kind.rawValue))" data-status="\(escape(item.statusLabel))">
          <header>
            <span data-testid="extension-kind">\(escape(item.kindLabel))</span>
            <span data-testid="extension-status">\(escape(item.statusLabel))</span>
          </header>
          <strong data-testid="extension-name">\(escape(item.name))</strong>
          \(item.summary.isEmpty ? "" : #"<p data-testid="extension-summary">\#(escape(item.summary))</p>"#)
          <code data-testid="extension-path">\(escape(item.relativePath))</code>
          \(item.launchCommand.map { #"<code data-testid="extension-command">\#(escape($0))</code>"# } ?? "")
          \(item.transportLabel.map { #"<span data-testid="extension-transport">\#(escape($0))</span>"# } ?? "")
          \(item.serverLabel.map { #"<span data-testid="extension-mcp-server">\#(escape($0))</span>"# } ?? "")
          \(item.protocolLabel.map { #"<span data-testid="extension-mcp-protocol">\#(escape($0))</span>"# } ?? "")
          \(item.toolCountLabel.map { #"<span data-testid="extension-mcp-tools-count">\#(escape($0))</span>"# } ?? "")
          \(renderMCPToolNames(item.toolNames))
          \(item.probeError.map { #"<p data-testid="extension-mcp-error">\#(escape($0))</p>"# } ?? "")
          \(renderExtensionActions(item))
        </article>
        """
    }

    private static func renderMCPToolNames(_ toolNames: [String]) -> String {
        guard !toolNames.isEmpty else { return "" }
        return #"<div data-testid="extension-mcp-tools">\#(toolNames.map { #"<span data-testid="extension-mcp-tool">\#(escape($0))</span>"# }.joined())</div>"#
    }

    private static func renderExtensionActions(_ item: ProjectExtensionManifestSurface) -> String {
        if let stopCommandID = item.stopCommandID {
            return #"<button type="button" data-testid="extension-stop" data-command="\#(escape(stopCommandID))">Stop</button>"#
        }
        if let startCommandID = item.startCommandID {
            return #"<button type="button" data-testid="extension-start" data-command="\#(escape(startCommandID))">Start</button>"#
        }
        return ""
    }

    private static func renderMemories(_ memories: WorkspaceMemoriesSurface) -> String {
        guard memories.isVisible else { return "" }
        let counts = """
        <span data-testid="memories-count">\(countLabel(memories.globalCount, singular: "global memory"))</span>
        <span data-testid="memories-count">\(countLabel(memories.projectCount, singular: "project memory"))</span>
        """
        let content: String
        if memories.items.isEmpty {
            content = """
            <div class="memories-empty" data-testid="memories-empty">
              <strong>\(escape(memories.emptyTitle))</strong>
              <p>\(escape(memories.emptySubtitle))</p>
            </div>
            """
        } else {
            content = """
            <div class="memories-grid" data-testid="memories-grid">
              \(memories.items.map(renderMemoryItem).joined(separator: "\n"))
            </div>
            """
        }
        return """
        <section class="memories-pane" data-testid="memories-pane" aria-label="QuillCode memories">
          <header>
            <div>
              <strong>\(escape(memories.title))</strong>
              <p data-testid="memories-subtitle">\(escape(memories.subtitle))</p>
            </div>
            <span class="memories-counts">
              \(counts)
            </span>
          </header>
          \(content)
        </section>
        """
    }

    private static func renderMemoryItem(_ item: MemoryNoteSurface) -> String {
        """
        <article class="memory-card" data-testid="memory-item" data-scope="\(escape(item.scope.rawValue))">
          <header>
            <span data-testid="memory-scope">\(escape(item.scopeLabel))</span>
            <span data-testid="memory-size">\(escape(item.byteCountLabel))</span>
            \(item.deleteCommandID.map { #"<button type="button" data-testid="memory-delete" data-command-id="\#(escape($0))">Forget</button>"# } ?? "")
          </header>
          <strong data-testid="memory-title">\(escape(item.title))</strong>
          <p data-testid="memory-preview">\(escape(item.preview))</p>
          <code data-testid="memory-path">\(escape(item.relativePath))</code>
        </article>
        """
    }

    private static func countLabel(_ count: Int, singular: String) -> String {
        if count == 1 { return "1 \(singular)" }
        if singular.hasSuffix("memory") {
            return "\(count) \(singular.dropLast("memory".count))memories"
        }
        return "\(count) \(singular)s"
    }

    private static func renderComposer(_ composer: ComposerSurface) -> String {
        let button = composer.isSending
            ? #"<button type="button" data-testid="stop-button">Stop</button>"#
            : #"<button type="submit" data-testid="send-button" \#(composer.canSend ? "" : "disabled")>Send</button>"#
        return """
        <form class="composer" data-testid="composer">
          <label for="message">Message</label>
          <input id="message" aria-label="Message" placeholder="\(escape(composer.placeholder))" value="\(escape(composer.draft))" \(composer.isSending ? "disabled" : "")>
          \(button)
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
