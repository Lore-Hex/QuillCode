import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section class="quillcode-workspace" data-testid="workspace">
          \(renderTopBar(surface.topBar, commands: surface.commands))
          <div class="workspace-grid">
            \(WorkspaceHTMLSidebarRenderer.render(
                projects: surface.projects,
                sidebar: surface.sidebar,
                commands: surface.commands
            ))
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
