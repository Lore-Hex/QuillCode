import Foundation

enum WorkspaceHTMLTranscriptRenderer {
    static func render(
        transcript: TranscriptSurface,
        contextBanner: ContextBannerSurface?,
        review: WorkspaceReviewSurface,
        runtimeIssue: RuntimeIssueSurface?,
        retryLastTurnCommand: WorkspaceCommandSurface?
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

    static func renderComposer(_ composer: ComposerSurface, topBar: TopBarSurface) -> String {
        let button = composer.isSending
            ? #"<button type="button" data-testid="stop-button">Stop</button>"#
            : #"<button type="submit" data-testid="send-button" \#(composer.canSend ? "" : "disabled")>Send</button>"#
        return """
        <form class="composer" data-testid="composer">
          <div class="composer-controls" data-testid="composer-controls" aria-label="Composer controls">
            <button type="button" class="composer-model-button" data-testid="model-picker-button" aria-label="Model: \(escape(topBar.modelLabel))">◇ <span data-testid="model-pill">\(escape(topBar.modelLabel))</span></button>
            <button type="button" class="mode-pill-button" data-testid="mode-picker-button" data-mode-tone="\(modeTone(for: topBar.modeLabel))" aria-label="Auto safety mode: \(escape(topBar.modeLabel))">
              <span class="mode-dot" aria-hidden="true"></span>
              <span data-testid="mode-pill">\(escape(topBar.modeLabel))</span>
            </button>
          </div>
          <label for="message">Message</label>
          <textarea id="message" aria-label="Message" placeholder="\(escape(composer.placeholder))" rows="1" \(composer.isSending ? "disabled" : "")>\(escape(composer.draft))</textarea>
          \(button)
        </form>
        """
    }

    private static func modeTone(for modeLabel: String) -> String {
        switch modeLabel.lowercased() {
        case "review":
            return "review"
        case "read-only":
            return "read-only"
        default:
            return "auto"
        }
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

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
