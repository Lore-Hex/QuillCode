import Foundation

public enum WorkspaceHTMLRenderer {
    public static func render(_ surface: WorkspaceSurface) -> String {
        """
        <section \(workspaceAttributes(for: surface.chrome))>
          \(WorkspaceHTMLTopBarRenderer.render(surface.topBar, commands: surface.commands))
          <div class="\(workspaceGridClass(for: surface))">
            \(sidebarHTML(for: surface))
            <main class="transcript" data-testid="transcript">
              \(incognitoBannerHTML(for: surface))
              \(sideConversationHTML(for: surface))
              \(WorkspaceHTMLSecondaryPaneRenderer.renderAutomations(surface.automations))
              \(WorkspaceHTMLTranscriptRenderer.render(
                transcript: surface.transcript,
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
              \(WorkspaceHTMLTranscriptRenderer.renderComposer(surface.composer, topBar: surface.topBar))
            </main>
          </div>
          \(attentionDigestHTML(for: surface))
        </section>
        """
    }

    /// The persistent incognito banner (control-free), mirroring the native
    /// `QuillCodeIncognitoBannerView` and the harness's `.incognito-banner`.
    private static func incognitoBannerHTML(for surface: WorkspaceSurface) -> String {
        guard surface.isIncognito else { return "" }
        return """
        <section class="incognito-banner" data-testid="incognito-banner" aria-label="Incognito chat: not saved, end-to-end encrypted">
          <strong data-testid="incognito-banner-title">Incognito chat</strong>
          <span data-testid="incognito-banner-detail">Not saved · E2E encrypted</span>
        </section>
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

    private static func workspaceAttributes(for chrome: WorkspaceChromeSurface) -> String {
        #"class="quillcode-workspace" data-testid="workspace" data-sidebar-visible="\#(chrome.isSidebarVisible)""#
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
