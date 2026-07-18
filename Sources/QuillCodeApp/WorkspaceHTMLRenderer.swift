import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section \(workspaceAttributes(for: surface))>
          \(WorkspaceHTMLTopBarRenderer.render(surface.topBar, commands: surface.commands))
          <div class="\(workspaceGridClass(for: surface))">
            \(sidebarHTML(for: surface))
            <main class="transcript" data-testid="transcript">
              \(confidentialBannerHTML(for: surface))
              \(sideConversationHTML(for: surface))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderAutomations(surface.automations))
              \(WorkspaceHTMLTranscriptRenderer.render(
                transcript: surface.transcript,
                contextBanner: surface.contextBanner,
                review: surface.review,
                runtimeIssue: surface.runtimeIssue,
                retryLastTurnCommand: surface.commands.first { $0.id == "retry-last-turn" && $0.isEnabled },
                isConfidential: surface.isConfidential
              ))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderExtensions(surface.extensions))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderMemories(surface.memories))
              \(WorkspaceHTMLBrowserRenderer.render(surface.browser))
              \(WorkspaceHTMLTerminalRenderer.render(surface.terminal))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderActivity(surface.activity))
              \(WorkspaceHTMLTranscriptRenderer.renderComposer(surface.composer, topBar: surface.topBar))
            </main>
          </div>
          \(autoReviewDenialsHTML(for: surface))
          \(attentionDigestHTML(for: surface))
        </section>
        """
    }

    /// The persistent confidential banner (control-free), mirroring the native
    /// `QuillCodeConfidentialBannerView` and the harness's `.confidential-banner`.
    private static func confidentialBannerHTML(for surface: WorkspaceSurface) -> String {
        guard surface.isConfidential else { return "" }
        return """
        <section class="confidential-banner" data-testid="confidential-banner" aria-label="Confidential chat: not saved, end-to-end encrypted">
          <strong data-testid="confidential-banner-title">Confidential chat</strong>
          <span data-testid="confidential-banner-detail">Not saved · E2E encrypted</span>
        </section>
        """
    }

    private static func autoReviewDenialsHTML(for surface: WorkspaceSurface) -> String {
        guard let denials = surface.autoReviewDenials else { return "" }
        let rows = denials.items.map { item in
            let metadata = [item.riskLabel.map { "\($0) risk" }, item.authorizationLabel]
                .compactMap(\.self)
                .map { #"<span>\#(WorkspaceHTMLPrimitives.escape($0))</span>"# }
                .joined()
            let retrying = denials.retryingRequestID == item.requestID
            let state = switch item.retryState {
            case .available: "Retry available"
            case .consumed: "Retry used"
            case .unavailable: "Cannot replay safely"
            case .contextChanged: "Context changed"
            }
            return """
            <article class="auto-review-denial" data-testid="auto-review-denial" data-request-id="\(WorkspaceHTMLPrimitives.escape(item.requestID))" data-retry-state="\(item.retryState.rawValue)">
              <header><strong>\(WorkspaceHTMLPrimitives.escape(item.toolName))</strong><span>\(state)</span></header>
              <p>\(WorkspaceHTMLPrimitives.escape(item.actionSummary))</p>
              <p>\(WorkspaceHTMLPrimitives.escape(item.reason))</p>
              <footer>\(metadata)\(WorkspaceHTMLPrimitives.commandButton(
                  retrying ? "Reviewing" : "Review and retry",
                  testID: "auto-review-denial-retry",
                  commandID: item.retryCommandID,
                  hitTargetKind: .text,
                  disabled: !item.canRetry || denials.retryingRequestID != nil,
                  attributes: [("data-request-id", item.requestID)]
              ))</footer>
            </article>
            """
        }.joined(separator: "\n")
        let body = rows.isEmpty
            ? #"<p data-testid="auto-review-denials-empty">No recent denials</p>"#
            : rows
        return """
        <div class="auto-review-denials-backdrop" data-testid="auto-review-denials-dialog" role="dialog" aria-modal="true" aria-label="Auto-review Denials">
          <section class="auto-review-denials-card">
            <header><div><h2>Auto-review Denials</h2><p>Retry one exact action. Auto will review it again before anything runs.</p></div>\(WorkspaceHTMLPrimitives.commandButton(
                "Done",
                testID: "auto-review-denials-close",
                commandID: WorkspaceCommandAction.dismissAutoReviewDenials.rawValue,
                hitTargetKind: .text
            ))</header>
            <div data-testid="auto-review-denials-list">\(body)</div>
          </section>
        </div>
        """
    }

    private static func sideConversationHTML(for surface: WorkspaceSurface) -> String {
        guard let side = surface.sideConversation else { return "" }
        return """
        <section class="side-conversation" data-testid="side-conversation" data-parent-thread-id="\(side.parentThreadID.uuidString)">
          <div>
            <strong data-testid="side-conversation-title">Side conversation</strong>
            <span data-testid="side-conversation-parent">From \(WorkspaceHTMLPrimitives.escape(side.parentTitle))</span>
            <span data-testid="side-conversation-status">\(WorkspaceHTMLPrimitives.escape(side.parentStatus))</span>
          </div>
          \(WorkspaceHTMLPrimitives.commandButton(
              side.returnCommand.title,
              testID: "side-conversation-return",
              commandID: side.returnCommand.id,
              hitTargetKind: .text,
              classes: ["side-conversation-return"]
          ))
        </section>
        """
    }

    /// The morning-triage return digest card overlay (issue #877), present only when a digest is open.
    /// Mirrors the native `QuillCodeAttentionDigestView` structure so the two surfaces stay in parity.
    private static func attentionDigestHTML(for surface: WorkspaceSurface) -> String {
        guard let digest = surface.attentionDigest else { return "" }
        let badge = (digest.badgeLabel).map {
            #"<span data-testid="attention-digest-verdict" data-verdict="\#(digest.verdict?.rawValue ?? "")">\#(WorkspaceHTMLPrimitives.escape($0))</span>"#
        } ?? ""
        let summary = digest.verdictSummary.isEmpty
            ? ""
            : #"<p data-testid="attention-digest-summary">\#(WorkspaceHTMLPrimitives.escape(digest.verdictSummary))</p>"#
        let seam = digest.unseenSeamLabel.map {
            #"<div data-testid="attention-digest-seam">\#(WorkspaceHTMLPrimitives.escape($0))</div>"#
        } ?? ""
        let reasons = digest.reasons.isEmpty ? "" : """
        <ul data-testid="attention-digest-reasons">
          \(digest.reasons.map { #"<li>\#(WorkspaceHTMLPrimitives.escape($0))</li>"# }.joined(separator: "\n"))
        </ul>
        """
        return """
        <div class="attention-digest-backdrop" data-testid="attention-digest" data-thread-id="\(digest.threadID.uuidString)">
          <div class="attention-digest-card">
            <div class="attention-digest-header">
              \(badge)
              <strong data-testid="attention-digest-title">\(WorkspaceHTMLPrimitives.escape(digest.title))</strong>
              \(WorkspaceHTMLPrimitives.commandButton(
                "Close",
                testID: "attention-digest-close",
                commandID: "attention-digest-close",
                hitTargetKind: .text,
                ariaLabel: "Close digest"
              ))
            </div>
            \(summary)
            \(seam)
            <div data-testid="attention-digest-outcome">\(WorkspaceHTMLPrimitives.escape(digest.outcome))</div>
            \(reasons)
            <div class="attention-digest-actions">
              \(WorkspaceHTMLPrimitives.commandButton(
                "Acknowledge",
                testID: "attention-digest-acknowledge",
                commandID: "attention-acknowledge",
                hitTargetKind: .text
              ))
              \(WorkspaceHTMLPrimitives.commandButton(
                "Dismiss",
                testID: "attention-digest-dismiss",
                commandID: "attention-dismiss",
                hitTargetKind: .text
              ))
            </div>
          </div>
        </div>
        """
    }

    private static func workspaceAttributes(for surface: WorkspaceSurface) -> String {
        // data-confidential flips the whole DOM surface into the violet confidential ramp via the
        // shared `[data-confidential="true"]` token overrides (see E2E/harness/index.html :root).
        #"class="quillcode-workspace" data-testid="workspace" data-sidebar-visible="\#(surface.chrome.isSidebarVisible)" data-confidential="\#(surface.isConfidential)""#
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
