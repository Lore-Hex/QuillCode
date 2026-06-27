import Foundation

enum WorkspaceHTMLBrowserRenderer {
    static func render(_ browser: BrowserSurface) -> String {
        guard browser.isVisible else { return "" }
        let preview = renderPreview(browser)
        let comments = browser.comments.map(renderComment).joined(separator: "\n")
        return """
        <section class="browser-pane" data-testid="browser-pane">
          <header>
            <strong>Browser</strong>
            <span data-testid="browser-status-label">\(escape(browser.statusLabel))</span>
          </header>
          \(renderTabs(browser))
          <form class="browser-form" data-testid="browser-form">
            <div class="browser-nav-controls" aria-label="Browser navigation">
              <button class="browser-nav-button" type="button" data-testid="browser-back" aria-label="Back" \(browser.canGoBack ? "" : "disabled")>Back</button>
              <button class="browser-nav-button" type="button" data-testid="browser-forward" aria-label="Forward" \(browser.canGoForward ? "" : "disabled")>Forward</button>
              <button class="browser-nav-button" type="button" data-testid="browser-reload" aria-label="Reload" \(browser.canReload ? "" : "disabled")>Reload</button>
            </div>
            <input data-testid="browser-address" aria-label="Browser address" value="\(escape(browser.addressDraft))">
            <button class="browser-open-button" type="submit" data-testid="browser-open" \(browser.canOpen ? "" : "disabled")>Open</button>
          </form>
          \(preview)
          <form class="browser-comment-form" data-testid="browser-comment-form">
            <input data-testid="browser-comment-input" aria-label="Browser comment" placeholder="Add browser comment">
            <button type="submit" data-testid="browser-add-comment" \(browser.currentURL == nil ? "disabled" : "")>Comment</button>
          </form>
          <div data-testid="browser-comments">
            \(comments)
          </div>
        </section>
        """
    }

    private static func renderTabs(_ browser: BrowserSurface) -> String {
        let tabs = browser.tabs.map { tab in
            """
            <button class="browser-tab \(WorkspaceHTMLPrimitives.capsuleHitTargetClass)\(tab.isActive ? " active" : "")" type="button" data-testid="browser-tab" data-command-id="\(escape(tab.selectCommandID))" aria-pressed="\(tab.isActive ? "true" : "false")">
              <span>\(escape(tab.title))</span>
              \(tab.urlLabel.map { #"<small>\#(escape($0))</small>"# } ?? "")
            </button>
            """
        }.joined(separator: "\n")
        return """
        <div class="browser-tabs" data-testid="browser-tabs">
          \(tabs)
          <button class="browser-tab-action \(WorkspaceHTMLPrimitives.iconHitTargetClass)" type="button" data-testid="browser-new-tab" data-command-id="browser-tab-new" aria-label="New browser tab">+</button>
          <button class="browser-tab-action \(WorkspaceHTMLPrimitives.iconHitTargetClass)" type="button" data-testid="browser-close-tab" data-command-id="browser-tab-close:\(browser.activeTabID.uuidString)" aria-label="Close browser tab" \(browser.canCloseActiveTab ? "" : "disabled")>×</button>
        </div>
        """
    }

    private static func renderPreview(_ browser: BrowserSurface) -> String {
        guard let currentURL = browser.currentURL else {
            return """
            <div class="browser-preview empty" data-testid="browser-empty">
              <strong>\(escape(browser.emptyTitle))</strong>
              <p>\(escape(browser.emptySubtitle))</p>
            </div>
            """
        }
        return """
        <div class="browser-preview" data-testid="browser-preview">
          <strong data-testid="browser-title">\(escape(browser.title))</strong>
          <code data-testid="browser-current-url">\(escape(currentURL))</code>
          \(renderSnapshot(browser.snapshot))
        </div>
        """
    }

    private static func renderSnapshot(_ snapshot: BrowserSnapshotSurface?) -> String {
        guard let snapshot else { return "" }
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
    }

    private static func renderComment(_ comment: BrowserCommentSurface) -> String {
        """
        <article data-testid="browser-comment">
          <p>\(escape(comment.text))</p>
          <small>\(escape(comment.url))</small>
        </article>
        """
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
