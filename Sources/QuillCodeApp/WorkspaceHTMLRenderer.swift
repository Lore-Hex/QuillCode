import Foundation
import QuillCodeTools

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section class="quillcode-workspace" data-testid="workspace">
          \(renderTopBar(surface.topBar, commands: surface.commands))
          <div class="workspace-grid">
            \(renderSidebar(projects: surface.projects, sidebar: surface.sidebar))
            <main class="transcript" data-testid="transcript">
              \(renderAutomations(surface.automations))
              \(renderTranscript(
                surface.transcript,
                contextBanner: surface.contextBanner,
                review: surface.review,
                runtimeIssue: surface.runtimeIssue,
                retryLastTurnCommand: surface.commands.first { $0.id == "retry-last-turn" && $0.isEnabled }
              ))
              \(renderExtensions(surface.extensions))
              \(renderMemories(surface.memories))
              \(renderBrowser(surface.browser))
              \(renderTerminal(surface.terminal))
              \(renderActivity(surface.activity))
              \(renderComposer(surface.composer))
            </main>
          </div>
        </section>
        """
    }

    private static func renderTopBar(_ topBar: TopBarSurface, commands: [WorkspaceCommandSurface]) -> String {
        """
        <header class="topbar" data-testid="top-bar" aria-label="QuillCode top bar">
          <div class="topbar-title-group" data-testid="top-bar-title-group">
            <span>
              <strong data-testid="top-bar-title">\(escape(topBar.primaryTitle))</strong>
              <p data-testid="top-bar-subtitle">\(escape(topBar.subtitle))</p>
            </span>
          </div>
          <div class="topbar-clusters" data-testid="top-bar-clusters">
            <div class="topbar-cluster topbar-primary-cluster" data-testid="top-bar-primary-cluster">
              <span data-testid="model-pill">\(escape(topBar.modelLabel)) · \(escape(topBar.modeLabel))</span>
              <span class="visually-hidden" data-testid="mode-pill">\(escape(topBar.modeLabel))</span>
            </div>
            <div class="topbar-cluster topbar-context-cluster" data-testid="top-bar-context-cluster" aria-label="Workspace state">
              <span class="agent-status-dot" data-testid="agent-status" title="\(escape(topBar.agentStatus))">\(escape(topBar.agentStatus))</span>
              \(topBar.runtimeIssueLabel.map { #"<span data-testid="runtime-issue-pill" data-severity="\#(escape(topBar.runtimeIssueSeverity?.rawValue ?? "warning"))">\#(escape($0))</span>"# } ?? "")
              <span data-testid="project-instructions-status" title="\(escape(topBar.instructionSources.joined(separator: ", ")))">\(escape(topBar.instructionLabel))</span>
              <span data-testid="project-memories-status" title="\(escape(topBar.memorySources.joined(separator: ", ")))">\(escape(topBar.memoryLabel))</span>
              <span data-testid="computer-use-status">\(escape(topBar.computerUseLabel))</span>
            </div>
            <div class="topbar-cluster topbar-action-cluster" data-testid="top-bar-action-cluster">
              <details class="topbar-overflow-menu" data-testid="top-bar-overflow-menu">
                <summary data-testid="top-bar-overflow-button" aria-label="More" title="More">...</summary>
                <div class="topbar-overflow-popover">
                  \(renderTopBarOverflow(commands: commands, showsComputerUseSetup: topBar.showsComputerUseSetup))
                </div>
              </details>
            </div>
          </div>
        </header>
        """
    }

    private static func renderTopBarOverflow(
        commands: [WorkspaceCommandSurface],
        showsComputerUseSetup: Bool
    ) -> String {
        TopBarOverflowCommandCatalog.commands(
            from: commands,
            showsComputerUseSetup: showsComputerUseSetup
        )
        .map(renderTopBarOverflowButton)
        .joined(separator: "\n")
    }

    private static func renderTopBarOverflowButton(_ command: WorkspaceCommandSurface) -> String {
        let testID = TopBarOverflowCommandCatalog.testID(for: command.id)
        let disabledAttribute = command.isEnabled ? "" : #" disabled aria-disabled="true""#
        let title = command.shortcut.map { "\(command.title) (\($0))" } ?? command.title
        return #"<button type="button" data-testid="\#(escape(testID))" data-command-id="\#(escape(command.id))" title="\#(escape(title))"\#(disabledAttribute)>\#(escape(command.title))</button>"#
    }

    private static func renderSidebar(projects: ProjectListSurface, sidebar: SidebarSurface) -> String {
        let projectContent: String
        if projects.items.isEmpty {
            projectContent = #"<p data-testid="project-empty">\#(escape(projects.emptyTitle))</p>"#
        } else {
            projectContent = projects.items.map { project in
                """
                <button class="project-item\(project.isSelected ? " selected" : "")" data-testid="project-item" data-project-id="\(project.id.uuidString)" aria-current="\(project.isSelected ? "true" : "false")">
                  <span>\(escape(project.name))\(project.isRemote ? #" <small data-testid="project-connection-kind">SSH Remote</small>"# : "")</span>
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
          <div class="sidebar-actions" aria-label="Primary chat actions">
            <button class="sidebar-action" type="button" data-testid="new-chat-button" data-primary="true">New chat</button>
            <button class="sidebar-action" type="button" data-testid="sidebar-search-button" data-primary="true">Search</button>
            <button class="sidebar-action" type="button" data-testid="extensions-button" data-primary="true">Plugins</button>
            <button class="sidebar-action" type="button" data-testid="automations-button" data-primary="true">Automations</button>
          </div>
          <div class="sidebar-title-row">
            <h2>\(escape(sidebar.title))</h2>
            \(renderSidebarSelectionHeaderAction(sidebar))
          </div>
          \(renderSidebarBulkToolbar(sidebar))
          \(content)
          <div class="sidebar-section-title">
            <h2>\(escape(projects.title))</h2>
            <button type="button" data-testid="add-project-button" aria-label="Open project">+</button>
          </div>
          \(projectContent)
          <div class="sidebar-footer" aria-label="Workspace tools">
            <details class="sidebar-tools-menu" data-testid="sidebar-tools-menu">
              <summary data-testid="sidebar-tools-button" aria-label="Tools" title="Tools">Tools</summary>
              <div class="sidebar-tools-popover" role="menu">
                <button class="sidebar-tool-action" type="button" data-testid="terminal-button" aria-label="Terminal" title="Terminal">Terminal</button>
                <button class="sidebar-tool-action" type="button" data-testid="browser-button" aria-label="Browser" title="Browser">Browser</button>
                <button class="sidebar-tool-action" type="button" data-testid="memories-button" aria-label="Memories" title="Memories">Memories</button>
                <button class="sidebar-tool-action" type="button" data-testid="activity-button" aria-label="Activity" title="Activity">Activity</button>
                <button class="sidebar-tool-action" type="button" data-testid="command-palette-button" aria-label="Command palette" title="Command palette">Command palette</button>
              </div>
            </details>
            <button class="sidebar-settings-button" type="button" data-testid="settings-button" aria-label="Settings" title="Settings">Settings</button>
          </div>
        </aside>
        """
    }

    private static func renderSidebarSection(title: String, items: [SidebarItemSurface]) -> String {
        guard !items.isEmpty else { return "" }
        let rows = items.map { item in
            """
            <div data-testid="sidebar-thread-row">
              \(item.isBulkSelected ? "<span data-testid=\"sidebar-thread-selected\">Selected</span>" : "")
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

    private static func renderSidebarBulkToolbar(_ sidebar: SidebarSurface) -> String {
        guard sidebar.isSelectionMode, !sidebar.bulkActions.isEmpty else { return "" }
        let actions = sidebar.bulkActions.map { action in
            """
            <button type="button" data-testid="sidebar-bulk-action" data-command-id="\(escape(action.commandID))" data-action="\(escape(action.kind.rawValue))" data-destructive="\(action.isDestructive)" \(action.isEnabled ? "" : "disabled")>\(escape(action.title))</button>
            """
        }.joined(separator: "\n")
        return """
        <div data-testid="sidebar-selection" data-active="\(sidebar.isSelectionMode)" data-selected-count="\(sidebar.selectedThreadIDs.count)">
          <span data-testid="sidebar-selection-label">\(escape(sidebar.selectionLabel))</span>
          \(actions)
        </div>
        """
    }

    private static func renderSidebarSelectionHeaderAction(_ sidebar: SidebarSurface) -> String {
        guard !sidebar.isSelectionMode,
              let action = sidebar.bulkActions.first(where: { $0.kind == .select })
        else { return "" }
        return """
        <button type="button" data-testid="sidebar-bulk-action" data-command-id="\(escape(action.commandID))" data-action="\(escape(action.kind.rawValue))" data-destructive="\(action.isDestructive)" \(action.isEnabled ? "" : "disabled")>\(escape(action.title))</button>
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
        runtimeIssue: RuntimeIssueSurface? = nil,
        retryLastTurnCommand: WorkspaceCommandSurface? = nil
    ) -> String {
        let context = renderContextBanner(contextBanner)
        let issue = renderRuntimeIssue(runtimeIssue)
        let reviewPane = renderReview(review)
        let latestAssistantMessageID = transcript.timelineItems
            .compactMap(\.message)
            .last(where: { $0.role == .assistant })?
            .id
        let timeline = transcript.timelineItems.map {
            renderTimelineItem(
                $0,
                latestAssistantMessageID: latestAssistantMessageID,
                retryLastTurnCommand: retryLastTurnCommand
            )
        }.joined(separator: "\n")
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

    private static func renderTimelineItem(
        _ item: TranscriptTimelineItemSurface,
        latestAssistantMessageID: UUID?,
        retryLastTurnCommand: WorkspaceCommandSurface?
    ) -> String {
        switch item.kind {
        case .message:
            guard let message = item.message else { return "" }
            return """
            <article class="message \(message.role.rawValue)" data-testid="message" data-timeline-id="\(escape(item.id))" aria-label="\(escape(message.accessibilityLabel))">
              <p>\(escape(message.text))</p>
              <footer class="transcript-actions">
                <button type="button" data-testid="message-copy" data-copy-id="\(escape(item.id))">Copy</button>
                \(renderMessageDraftAction(message))
                \(renderMessageRetryAction(message, latestAssistantMessageID: latestAssistantMessageID, command: retryLastTurnCommand))
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

    private static func renderMessageDraftAction(_ message: MessageSurface) -> String {
        guard message.role == .user else { return "" }
        return #"<button type="button" data-testid="message-use-as-draft" data-message-id="\#(message.id.uuidString)">Use as draft</button>"#
    }

    private static func renderMessageRetryAction(
        _ message: MessageSurface,
        latestAssistantMessageID: UUID?,
        command: WorkspaceCommandSurface?
    ) -> String {
        guard message.role == .assistant,
              message.id == latestAssistantMessageID,
              let command
        else { return "" }
        return #"<button type="button" data-testid="message-retry" data-command-id="\#(escape(command.id))">\#(escape(command.title))</button>"#
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
        let executionContextAttribute = card.executionContext
            .map { #" data-execution-context="\#(escape($0.kind.rawValue))""# } ?? ""
        let accessibilityContext = card.executionContext
            .map { ", \($0.label) \($0.detail)" } ?? ""
        let copyID = timelineItemID ?? card.id
        return """
        <article class="tool-card \(card.status.rawValue)" data-testid="tool-card" data-status="\(card.status.rawValue)" data-density="\(card.density.rawValue)" aria-label="\(escape(card.title)), \(escape(card.status.rawValue)), \(escape(card.densityAccessibilityLabel))\(escape(accessibilityContext))"\(timelineAttribute)\(executionContextAttribute)>
          <header>
            <span class="tool-card-title-row">
              <strong data-testid="tool-card-title">\(escape(card.title))</strong>
              \(renderExecutionContextChip(card.executionContext, testID: "tool-card-execution-context"))
            </span>
            <span data-testid="tool-card-status">\(escape(card.status.rawValue))</span>
          </header>
          <p data-testid="tool-card-subtitle">\(escape(card.subtitle))</p>
          <footer class="transcript-actions">
            <button type="button" data-testid="tool-card-copy" data-copy-id="\(escape(copyID))">\(escape(copyActionLabel(for: card)))</button>
          </footer>
          \(renderToolArtifacts(card.artifacts))
          \(renderToolTextPreviews(card.artifacts))
          \(renderToolDocumentPreviews(card.artifacts))
          \(renderToolImagePreviews(card.artifacts))
          \(renderToolDetails(card))
        </article>
        """
    }

    private static func renderExecutionContextChip(
        _ context: ExecutionContextSurface?,
        testID: String
    ) -> String {
        guard let context else { return "" }
        let title: String
        switch context.kind {
        case .local:
            title = context.label
        case .sshRemote:
            title = "\(context.label) · \(context.detail)"
        }
        return """
        <span class="execution-context-chip" data-testid="\(escape(testID))" data-execution-context-kind="\(escape(context.kind.rawValue))">\(escape(title))</span>
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
        let isOpen = card.opensDetailsByDefault
        return """
        <details data-testid="tool-card-details"\(isOpen ? " open" : "")>
          <summary>\(isOpen ? "Hide details" : "Show raw details")</summary>
          \(card.inputJSON.map { #"<pre data-testid="tool-card-input">\#(escape($0))</pre>"# } ?? "")
          \(card.outputJSON.map { #"<pre data-testid="tool-card-output">\#(escape($0))</pre>"# } ?? "")
        </details>
        """
    }

    private static func renderToolArtifacts(_ artifacts: [ToolArtifactState]) -> String {
        guard !artifacts.isEmpty else { return "" }
        let chips = artifacts.map { artifact in
            let href = artifact.href.map { #" href="\#(escape($0))""# } ?? ""
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

    private static func renderToolTextPreviews(_ artifacts: [ToolArtifactState]) -> String {
        let textArtifacts = artifacts.filter(\.hasTextPreview)
        guard !textArtifacts.isEmpty else { return "" }
        let previews = textArtifacts.map { artifact in
            """
            <figure class="artifact-text-preview" data-testid="tool-card-text-preview">
              <figcaption data-testid="tool-card-text-preview-label">\(escape(artifact.label))</figcaption>
              <pre data-testid="tool-card-text-preview-content">\(escape(artifact.textPreview ?? ""))</pre>
            </figure>
            """
        }.joined(separator: "\n")
        return """
        <div class="tool-artifact-text-previews" data-testid="tool-card-text-previews" aria-label="Text previews">
          \(previews)
        </div>
        """
    }

    private static func renderToolDocumentPreviews(_ artifacts: [ToolArtifactState]) -> String {
        let documentArtifacts = artifacts.filter(\.isDocumentPreview)
        guard !documentArtifacts.isEmpty else { return "" }
        let previews = documentArtifacts.compactMap { artifact -> String? in
            guard let preview = artifact.documentPreview else { return nil }
            let openLink = artifact.href.map {
                #"<a data-testid="tool-card-document-preview-open" href="\#(escape($0))">Open</a>"#
            } ?? ""
            return """
            <figure class="artifact-document-preview" data-testid="tool-card-document-preview" data-kind="\(escape(preview.kind.rawValue))">
              <span class="artifact-document-icon" aria-hidden="true">\(documentIcon(for: preview.kind))</span>
              <figcaption>
                <small data-testid="tool-card-document-preview-type">\(escape(preview.typeLabel)) · \(escape(preview.extensionLabel))</small>
                <strong data-testid="tool-card-document-preview-label">\(escape(artifact.label))</strong>
                <small data-testid="tool-card-document-preview-detail">\(escape(preview.detail))</small>
              </figcaption>
              \(openLink)
            </figure>
            """
        }.joined(separator: "\n")
        guard !previews.isEmpty else { return "" }
        return """
        <div class="tool-artifact-document-previews" data-testid="tool-card-document-previews" aria-label="Document previews">
          \(previews)
        </div>
        """
    }

    private static func renderToolImagePreviews(_ artifacts: [ToolArtifactState]) -> String {
        let imageArtifacts = artifacts.filter(\.isImagePreview)
        guard !imageArtifacts.isEmpty else { return "" }
        let previews = imageArtifacts.compactMap { artifact -> String? in
            guard let src = artifact.previewURL,
                  let preview = artifact.imagePreview
            else { return nil }
            return """
            <figure class="artifact-preview" data-testid="tool-card-image-preview" data-kind="image">
              <img src="\(escape(src))" alt="\(escape(artifact.label))" loading="lazy">
              <figcaption>
                <small data-testid="tool-card-image-preview-type">\(escape(preview.typeLabel)) · \(escape(preview.extensionLabel))</small>
                <strong data-testid="tool-card-image-preview-label">\(escape(artifact.label))</strong>
                <small data-testid="tool-card-image-preview-detail">\(escape(preview.detail))</small>
              </figcaption>
            </figure>
            """
        }.joined(separator: "\n")
        guard !previews.isEmpty else { return "" }
        return """
        <div class="tool-artifact-previews" data-testid="tool-card-image-previews" aria-label="Image previews">
          \(previews)
        </div>
        """
    }

    private static func documentIcon(for kind: ToolArtifactDocumentKind) -> String {
        switch kind {
        case .appshot:
            return "APP"
        case .pdf:
            return "PDF"
        case .document:
            return "DOC"
        case .spreadsheet:
            return "XLS"
        case .presentation:
            return "PPT"
        }
    }

    private static func renderTerminal(_ terminal: TerminalSurface) -> String {
        guard terminal.isVisible else { return "" }
        let entries = terminal.entries.isEmpty
            ? #"<p data-testid="terminal-empty">\#(escape(terminal.emptyTitle))</p>"#
            : terminal.entries.map { entry in
                """
                <article class="terminal-entry" data-testid="terminal-entry"\(entry.executionContext.map { #" data-execution-context="\#(escape($0.kind.rawValue))""# } ?? "")>
                  <header>
                    <span class="terminal-command-row">
                      <code>$ \(escape(entry.command))</code>
                      \(renderExecutionContextChip(entry.executionContext, testID: "terminal-execution-context"))
                    </span>
                    <span class="terminal-status \(terminalStatusClass(entry))" data-testid="terminal-status">\(escape(entry.statusLabel)) · \(escape(entry.exitCodeLabel))</span>
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
            <button type="button" data-testid="terminal-clear" \(terminal.canClear ? "" : "disabled")>Clear</button>
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

    private static func terminalStatusClass(_ entry: TerminalCommandSurface) -> String {
        if entry.isSuccess {
            return "ok"
        }
        if entry.isRunning {
            return "running"
        }
        if entry.isStopped {
            return "stopped"
        }
        return "failed"
    }

    private static func renderBrowser(_ browser: BrowserSurface) -> String {
        guard browser.isVisible else { return "" }
        let snapshot = browser.snapshot.map { snapshot in
            let outline = snapshot.outline.isEmpty ? "" : """
              <ol data-testid="browser-snapshot-outline">
                \(snapshot.outline.map { #"<li data-testid="browser-snapshot-outline-item">\#(escape($0))</li>"# }.joined(separator: "\n"))
              </ol>
            """
            let textSnippet = snapshot.textSnippet.map {
                #"<p data-testid="browser-snapshot-text">\#(escape($0))</p>"#
            } ?? ""
            return """
            <div class="browser-snapshot" data-testid="browser-snapshot">
              <div class="browser-snapshot-badges">
                <span data-testid="browser-source">\(escape(snapshot.sourceLabel))</span>
                <span data-testid="browser-inspection-depth" data-depth="\(escape(snapshot.inspectionDepth.rawValue))">\(escape(snapshot.inspectionDepthLabel))</span>
              </div>
              <p data-testid="browser-snapshot-summary">\(escape(snapshot.summary))</p>
              <ul>
                \(snapshot.details.map { #"<li data-testid="browser-snapshot-detail">\#(escape($0))</li>"# }.joined(separator: "\n"))
              </ul>
              \(outline)
              \(textSnippet)
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
            <button type="button" data-testid="browser-back" \(browser.canGoBack ? "" : "disabled")>Back</button>
            <button type="button" data-testid="browser-forward" \(browser.canGoForward ? "" : "disabled")>Forward</button>
            <button type="button" data-testid="browser-reload" \(browser.canReload ? "" : "disabled")>Reload</button>
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
          \(item.versionLabel.map { #"<span data-testid="extension-version">\#(escape($0))</span>"# } ?? "")
          \(item.sourceURL.map { #"<code data-testid="extension-source">\#(escape($0))</code>"# } ?? "")
          <code data-testid="extension-path">\(escape(item.relativePath))</code>
          \(item.launchCommand.map { #"<code data-testid="extension-command">\#(escape($0))</code>"# } ?? "")
          \(item.updateCommand.map { #"<code data-testid="extension-update-command">\#(escape($0))</code>"# } ?? "")
          \(item.transportLabel.map { #"<span data-testid="extension-transport">\#(escape($0))</span>"# } ?? "")
          \(item.serverLabel.map { #"<span data-testid="extension-mcp-server">\#(escape($0))</span>"# } ?? "")
          \(renderMCPMeta(item))
          \(renderMCPTools(item.toolDescriptors))
          \(renderMCPNames("Resources", item.resourceNames, groupTestID: "extension-mcp-resources", itemTestID: "extension-mcp-resource"))
          \(renderMCPNames("Prompts", item.promptNames, groupTestID: "extension-mcp-prompts", itemTestID: "extension-mcp-prompt"))
          \(item.probeError.map { #"<p data-testid="extension-mcp-error">\#(escape($0))</p>"# } ?? "")
          \(renderExtensionActions(item))
        </article>
        """
    }

    private static func renderMCPMeta(_ item: ProjectExtensionManifestSurface) -> String {
        let labels = [
            item.protocolLabel.map { #"<span data-testid="extension-mcp-protocol">\#(escape($0))</span>"# },
            item.toolCountLabel.map { #"<span data-testid="extension-mcp-tools-count">\#(escape($0))</span>"# },
            item.resourceCountLabel.map { #"<span data-testid="extension-mcp-resources-count">\#(escape($0))</span>"# },
            item.promptCountLabel.map { #"<span data-testid="extension-mcp-prompts-count">\#(escape($0))</span>"# }
        ].compactMap { $0 }
        guard !labels.isEmpty else { return "" }
        return #"<div class="extension-mcp-meta" data-testid="extension-mcp-meta">\#(labels.joined(separator: " · "))</div>"#
    }

    private static func renderMCPTools(_ tools: [MCPToolDescriptor]) -> String {
        guard !tools.isEmpty else { return "" }
        let chips = tools.map { tool in
            let details = [tool.schemaSummary, tool.description]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return """
            <span class="extension-mcp-tool-chip" data-testid="extension-mcp-tool">
              <strong data-testid="extension-mcp-tool-name">\(escape(tool.name))</strong>
              \(details.isEmpty ? "" : #"<small data-testid="extension-mcp-tool-schema">\#(escape(details))</small>"#)
            </span>
            """
        }.joined()
        return #"<div class="extension-mcp-group" data-testid="extension-mcp-tools"><span class="extension-mcp-group-label" data-testid="extension-mcp-group-label">Tools</span><div class="extension-mcp-chip-row">\#(chips)</div></div>"#
    }

    private static func renderMCPNames(_ title: String, _ names: [String], groupTestID: String, itemTestID: String) -> String {
        guard !names.isEmpty else { return "" }
        let chips = names.map { #"<span data-testid="\#(escape(itemTestID))">\#(escape($0))</span>"# }.joined()
        return #"<div class="extension-mcp-group" data-testid="\#(escape(groupTestID))"><span class="extension-mcp-group-label" data-testid="extension-mcp-group-label">\#(escape(title))</span><div class="extension-mcp-chip-row">\#(chips)</div></div>"#
    }

    private static func renderExtensionActions(_ item: ProjectExtensionManifestSurface) -> String {
        var buttons: [String] = []
        if let updateCommandID = item.updateCommandID {
            buttons.append(#"<button type="button" data-testid="extension-update" data-command="\#(escape(updateCommandID))">Update</button>"#)
        }
        if let stopCommandID = item.stopCommandID {
            buttons.append(#"<button type="button" data-testid="extension-stop" data-command="\#(escape(stopCommandID))">Stop</button>"#)
        }
        if let startCommandID = item.startCommandID {
            buttons.append(#"<button type="button" data-testid="extension-start" data-command="\#(escape(startCommandID))">Start</button>"#)
        }
        return buttons.joined(separator: "\n")
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

    private static func renderActivity(_ activity: WorkspaceActivitySurface) -> String {
        guard activity.isVisible else { return "" }
        return """
        <section class="activity-pane" data-testid="activity-pane" aria-label="Task activity">
          <header>
            <div>
              <strong data-testid="activity-title">\(escape(activity.title))</strong>
              <p data-testid="activity-subtitle">\(escape(activity.subtitle))</p>
            </div>
            <span data-testid="activity-status">\(escape(activity.statusLabel))</span>
          </header>
          <article class="activity-task" data-testid="activity-task">
            <strong data-testid="activity-task-title">\(escape(activity.taskTitle))</strong>
            <p data-testid="activity-task-subtitle">\(escape(activity.taskSubtitle))</p>
          </article>
          \(activity.sections.map(renderActivitySection).joined(separator: "\n"))
        </section>
        """
    }

    private static func renderAutomations(_ automations: WorkspaceAutomationsSurface) -> String {
        guard automations.isVisible else { return "" }
        let content: String
        if automations.workflows.isEmpty {
            content = """
            <article class="automation-empty" data-testid="automations-empty">
              <strong>\(escape(automations.emptyTitle))</strong>
              <p>\(escape(automations.emptySubtitle))</p>
            </article>
            """
        } else {
            content = automations.workflows.map { workflow in
                let actions = renderAutomationActions(workflow)
                return """
                <article class="automation-card" data-testid="automation-card">
                  <div>
                    <span data-testid="automation-schedule">\(escape(workflow.scheduleLabel))</span>
                    <span data-testid="automation-status">\(escape(workflow.statusLabel))</span>
                  </div>
                  <strong>\(escape(workflow.title))</strong>
                  <p>\(escape(workflow.detail))</p>
                  \(actions)
                </article>
                """
            }.joined(separator: "\n")
        }
        let createButton = automations.createThreadFollowUpCommand.map { command in
            #"<button type="button" data-testid="automation-create-follow-up" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        } ?? ""
        let createWorkspaceButton = automations.createWorkspaceScheduleCommand.map { command in
            #"<button type="button" data-testid="automation-create-workspace-schedule" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        } ?? ""
        let scheduleButtons = automations.scheduleThreadFollowUpCommands.map { command in
            #"<button type="button" data-testid="automation-schedule-follow-up" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        }.joined(separator: "\n")
        let workspaceScheduleButtons = automations.scheduleWorkspaceScheduleCommands.map { command in
            #"<button type="button" data-testid="automation-schedule-workspace" data-command-id="\#(escape(command.id))" \#(command.isEnabled ? "" : "disabled")>\#(escape(command.title))</button>"#
        }.joined(separator: "\n")
        let createActions = [createButton, createWorkspaceButton, scheduleButtons, workspaceScheduleButtons]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return """
        <section class="automations-pane" data-testid="automations-pane" aria-label="Automations">
          <header>
            <div>
              <strong data-testid="automations-title">\(escape(automations.title))</strong>
              <p data-testid="automations-subtitle">\(escape(automations.subtitle))</p>
            </div>
            <div class="automation-create-actions">
              \(createActions)
            </div>
            <span data-testid="automations-status">\(escape(automations.statusLabel))</span>
          </header>
          <div class="automation-grid">
            \(content)
          </div>
        </section>
        """
    }

    private static func renderAutomationActions(_ workflow: AutomationWorkflowSurface) -> String {
        var buttons: [String] = []
        if let commandID = workflow.runCommandID,
           let title = workflow.runActionTitle {
            buttons.append(#"<button type="button" data-testid="automation-run" data-command-id="\#(escape(commandID))">\#(escape(title))</button>"#)
        }
        if let commandID = workflow.primaryCommandID,
           let title = workflow.primaryActionTitle {
            buttons.append(#"<button type="button" data-testid="automation-primary-action" data-command-id="\#(escape(commandID))">\#(escape(title))</button>"#)
        }
        if let commandID = workflow.deleteCommandID {
            buttons.append(#"<button type="button" data-testid="automation-delete" data-command-id="\#(escape(commandID))">Delete</button>"#)
        }
        guard !buttons.isEmpty else { return "" }
        return #"<div class="automation-actions">\#(buttons.joined(separator: "\n"))</div>"#
    }

    private static func renderActivitySection(_ section: ActivitySectionSurface) -> String {
        let content: String
        if section.isCollapsed {
            content = ""
        } else if let bodyText = section.bodyText {
            content = #"<p data-testid="\#(escape(section.itemTestID))" style="white-space: pre-wrap;">\#(escape(bodyText))</p>"#
        } else if !section.artifacts.isEmpty {
            content = section.artifacts.map { artifact in
                """
                <article class="activity-artifact" data-testid="\(escape(section.itemTestID))">
                  <strong>\(escape(artifact.label))</strong>
                  <p>\(escape(artifact.detail))</p>
                </article>
                """
            }.joined(separator: "\n")
        } else if !section.items.isEmpty {
            content = section.items.map { item in
                """
                <article class="activity-item" data-testid="\(escape(section.itemTestID))" data-kind="\(escape(item.kind))">
                  <strong>\(escape(item.title))</strong>
                  \(item.statusLabel.isEmpty ? "" : #"<span>\#(escape(item.statusLabel))</span>"#)
                  \(item.detail.isEmpty ? "" : #"<p>\#(escape(item.detail))</p>"#)
                </article>
                """
            }.joined(separator: "\n")
        } else {
            content = #"<p data-testid="\#(escape(section.itemTestID))-empty">\#(escape(section.emptyTitle))</p>"#
        }
        return """
        <section class="activity-section" data-testid="\(escape(section.itemTestID))-section" data-collapsed="\(section.isCollapsed ? "true" : "false")">
          <button type="button" data-testid="activity-section-toggle" data-command-id="\(escape(section.toggleCommandID))">
            <span>\(section.isCollapsed ? ">" : "v") \(escape(section.title))</span>
            <span>\(escape(section.countLabel))</span>
          </button>
          \(content)
        </section>
        """
    }

    private static func renderComposer(_ composer: ComposerSurface) -> String {
        let button = composer.isSending
            ? #"<button type="button" data-testid="stop-button">Stop</button>"#
            : #"<button type="submit" data-testid="send-button" \#(composer.canSend ? "" : "disabled")>Send</button>"#
        return """
        <form class="composer" data-testid="composer">
          <label for="message">Message</label>
          <textarea id="message" aria-label="Message" placeholder="\(escape(composer.placeholder))" rows="1" \(composer.isSending ? "disabled" : "")>\(escape(composer.draft))</textarea>
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
