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
