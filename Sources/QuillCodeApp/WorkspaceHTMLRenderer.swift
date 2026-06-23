import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section class="quillcode-workspace" data-testid="workspace">
          \(renderTopBar(surface.topBar, commands: surface.commands))
          <div class="workspace-grid">
            \(renderSidebar(projects: surface.projects, sidebar: surface.sidebar, commands: surface.commands))
            <main class="transcript" data-testid="transcript">
              \(WorkspaceHTMLSecondaryPaneRenderer.renderAutomations(surface.automations))
              \(renderTranscript(
                surface.transcript,
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

    private static func renderSidebar(
        projects: ProjectListSurface,
        sidebar: SidebarSurface,
        commands: [WorkspaceCommandSurface]
    ) -> String {
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
            \(renderSidebarPrimaryActions(commands))
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

    private static func renderSidebarPrimaryActions(_ commands: [WorkspaceCommandSurface]) -> String {
        QuillCodeSidebarCommandPresentation.primaryCommandIDs
            .compactMap { commandID in
                commands.first { $0.id == commandID }
            }
            .map { command in
                let testID = QuillCodeSidebarCommandPresentation.htmlTestID(for: command.id)
                let icon = QuillCodeSidebarCommandPresentation.htmlIconToken(for: command.id)
                let title = QuillCodeSidebarCommandPresentation.displayTitle(for: command)
                let disabled = command.isEnabled ? "" : #" disabled aria-disabled="true""#
                return #"<button class="sidebar-action" type="button" data-testid="\#(escape(testID))" data-primary="true" data-icon="\#(escape(icon))" data-command-id="\#(escape(command.id))"\#(disabled)>\#(escape(title))</button>"#
            }
            .joined(separator: "\n")
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
        let reviewPane = WorkspaceHTMLReviewRenderer.render(review)
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
            return WorkspaceHTMLToolCardRenderer.render(card, timelineItemID: item.id)
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
        WorkspaceHTMLPrimitives.escape(text)
    }
}
