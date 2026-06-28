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
        let thinking = renderThinking(transcript.thinking)
        if context.isEmpty && issue.isEmpty && timeline.isEmpty && thinking.isEmpty && !review.isVisible {
            return """
            <section class="empty" data-testid="transcript-empty">
              <h1>\(escape(transcript.emptyTitle))</h1>
              <p>\(escape(transcript.emptySubtitle))</p>
              \(renderStarterActions(transcript.emptyStarterActions))
            </section>
            """
        }
        return context + "\n" + issue + "\n" + reviewPane + "\n" + timeline + "\n" + thinking
    }

    static func renderComposer(_ composer: ComposerSurface, topBar: TopBarSurface) -> String {
        let button = composer.isSending
            ? WorkspaceHTMLPrimitives.button("Stop", testID: "stop-button")
            : WorkspaceHTMLPrimitives.button(
                "Send",
                testID: "send-button",
                type: "submit",
                classes: [WorkspaceHTMLPrimitives.iconHitTargetClass],
                disabled: !composer.canSend
            )
        return """
        <form class="composer" data-testid="composer">
          <div class="composer-surface" data-testid="composer-surface">
            <label class="composer-sr-only" for="message">Message</label>
            <div class="composer-input-row">
              <textarea id="message" aria-label="Message" placeholder="\(escape(composer.placeholder))" rows="1" \(composer.isSending ? "disabled" : "")>\(escape(composer.draft))</textarea>
              \(button)
            </div>
            <div class="composer-controls" data-testid="composer-controls" aria-label="Composer model and safety controls">
              <button\(WorkspaceHTMLPrimitives.buttonAttributes(
                  testID: "model-picker-button",
                  classes: ["composer-model-button", WorkspaceHTMLPrimitives.capsuleHitTargetClass],
                  ariaLabel: "Model: \(topBar.modelLabel)"
              ))>◇ <span data-testid="model-pill">\(escape(topBar.modelLabel))</span></button>
              <button\(WorkspaceHTMLPrimitives.buttonAttributes(
                  testID: "mode-picker-button",
                  classes: ["mode-pill-button", WorkspaceHTMLPrimitives.capsuleHitTargetClass],
                  ariaLabel: "Auto safety mode: \(topBar.modeLabel)",
                  attributes: [("data-mode-tone", modeTone(for: topBar.modeLabel))]
              ))>
                <span class="mode-dot" aria-hidden="true"></span>
                <span data-testid="mode-pill">\(escape(topBar.modeLabel))</span>
              </button>
            </div>
          </div>
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

    private static func renderStarterActions(_ actions: [TranscriptStarterActionSurface]) -> String {
        guard !actions.isEmpty else { return "" }
        return """
        <div class="empty-starters" data-testid="empty-starter-actions">
          \(actions.map { action in
            """
            <button\(WorkspaceHTMLPrimitives.buttonAttributes(
                testID: "empty-starter-action",
                classes: ["empty-starter", WorkspaceHTMLPrimitives.rowHitTargetClass],
                attributes: [
                    ("data-action-id", action.id),
                    ("data-prompt", action.prompt)
                ]
            ))><strong>\(escape(action.title))</strong><span>\(escape(action.subtitle))</span></button>
            """
          }.joined(separator: "\n"))
        </div>
        """
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
          \(issue.actionLabel.map { WorkspaceHTMLPrimitives.button($0, testID: "runtime-issue-action") } ?? "")
          \(diagnostics)
        </section>
        """
    }

    private static func renderThinking(_ thinking: TranscriptThinkingSurface?) -> String {
        guard let thinking else { return "" }
        let trace = thinking.traceLines.isEmpty ? "" : """
          <details data-testid="thinking-trace">
            <summary>\(escape(thinking.traceTitle))</summary>
            <ul>
              \(thinking.traceLines.map { #"<li>\#(escape($0))</li>"# }.joined(separator: "\n"))
            </ul>
          </details>
        """
        return """
        <article class="thinking" data-testid="thinking-indicator" data-thinking-id="\(escape(thinking.id))" aria-label="\(escape(thinking.title)): \(escape(thinking.subtitle))">
          <header>
            <strong data-testid="thinking-title">\(escape(thinking.title))</strong>
            <span aria-hidden="true">...</span>
          </header>
          <p data-testid="thinking-subtitle">\(escape(thinking.subtitle))</p>
          \(trace)
        </article>
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
                \(WorkspaceHTMLPrimitives.button(
                    "Copy",
                    testID: "message-copy",
                    attributes: [("data-copy-id", item.id)]
                ))
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
        \(WorkspaceHTMLPrimitives.button(
            "Helpful",
            testID: "message-feedback-up",
            attributes: [
                ("data-message-id", message.id.uuidString),
                ("data-selected", helpfulSelected)
            ]
        ))
        \(WorkspaceHTMLPrimitives.button(
            "Not helpful",
            testID: "message-feedback-down",
            attributes: [
                ("data-message-id", message.id.uuidString),
                ("data-selected", notHelpfulSelected)
            ]
        ))
        """
    }

    private static func renderMessageDraftAction(_ message: MessageSurface) -> String {
        guard message.role == .user else { return "" }
        return WorkspaceHTMLPrimitives.button(
            "Use as draft",
            testID: "message-use-as-draft",
            attributes: [("data-message-id", message.id.uuidString)]
        )
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
        return WorkspaceHTMLPrimitives.commandButton(
            command.title,
            testID: "message-retry",
            commandID: command.id
        )
    }

    private static func renderContextBanner(_ banner: ContextBannerSurface?) -> String {
        guard let banner else { return "" }
        let forkButtons = banner.forkCommands.map { command in
            let testID = WorkspaceThreadForkStrategy(commandID: command.id)?.contextBannerTestID ?? "context-fork"
            return WorkspaceHTMLPrimitives.commandButton(command.title, testID: testID, commandID: command.id)
        }.joined(separator: "\n            ")
        return """
        <section class="context-banner" data-testid="context-banner" aria-label="Context limit warning">
          <header>
            <strong data-testid="context-banner-title">\(escape(banner.title))</strong>
            <span data-testid="context-banner-percent">\(banner.usedPercent)%</span>
          </header>
          <p data-testid="context-banner-subtitle">\(escape(banner.subtitle))</p>
          <div>
            \(WorkspaceHTMLPrimitives.commandButton(banner.compactCommand.title, testID: "context-compact", commandID: banner.compactCommand.id))
            \(WorkspaceHTMLPrimitives.commandButton(banner.newThreadCommand.title, testID: "context-new-thread", commandID: banner.newThreadCommand.id))
            \(forkButtons)
          </div>
        </section>
        """
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
