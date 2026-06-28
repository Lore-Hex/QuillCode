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
              \(browserNavButton("Back", testID: "browser-back", isEnabled: browser.canGoBack))
              \(browserNavButton("Forward", testID: "browser-forward", isEnabled: browser.canGoForward))
              \(browserNavButton("Reload", testID: "browser-reload", isEnabled: browser.canReload))
            </div>
            <input\(WorkspaceHTMLPrimitives.hitTargetAttributes(for: WorkspaceHTMLPrimitives.textEntryHitTargetClass)) data-testid="browser-address" aria-label="Browser address" value="\(escape(browser.addressDraft))">
            \(WorkspaceHTMLPrimitives.button(
                "Open",
                testID: "browser-open",
                type: "submit",
                classes: ["browser-open-button", WorkspaceHTMLPrimitives.textHitTargetClass],
                disabled: !browser.canOpen
            ))
          </form>
          \(preview)
          <form class="browser-comment-form" data-testid="browser-comment-form">
            <input\(WorkspaceHTMLPrimitives.hitTargetAttributes(for: WorkspaceHTMLPrimitives.textEntryHitTargetClass)) data-testid="browser-comment-input" aria-label="Browser comment" placeholder="Add browser comment">
            \(WorkspaceHTMLPrimitives.button(
                "Comment",
                testID: "browser-add-comment",
                type: "submit",
                disabled: browser.currentURL == nil
            ))
          </form>
          <div data-testid="browser-comments">
            \(comments)
          </div>
        </section>
        """
    }

    private static func browserNavButton(
        _ label: String,
        testID: String,
        isEnabled: Bool
    ) -> String {
        WorkspaceHTMLPrimitives.button(
            label,
            testID: testID,
            classes: ["browser-nav-button", WorkspaceHTMLPrimitives.iconHitTargetClass],
            ariaLabel: label,
            disabled: !isEnabled
        )
    }

    private static func renderTabs(_ browser: BrowserSurface) -> String {
        let tabs = browser.tabs.map { tab in
            """
            <button\(WorkspaceHTMLPrimitives.buttonAttributes(
                testID: "browser-tab",
                classes: ["browser-tab", WorkspaceHTMLPrimitives.capsuleHitTargetClass, tab.isActive ? "active" : ""],
                attributes: [
                    ("data-command-id", tab.selectCommandID),
                    ("aria-pressed", tab.isActive ? "true" : "false")
                ]
            ))>
              <span>\(escape(tab.title))</span>
              \(tab.urlLabel.map { #"<small>\#(escape($0))</small>"# } ?? "")
            </button>
            """
        }.joined(separator: "\n")
        return """
        <div class="browser-tabs" data-testid="browser-tabs">
          \(tabs)
          \(WorkspaceHTMLPrimitives.commandButton(
              "+",
              testID: "browser-new-tab",
              commandID: "browser-tab-new",
              classes: ["browser-tab-action", WorkspaceHTMLPrimitives.iconHitTargetClass],
              ariaLabel: "New browser tab"
          ))
          \(WorkspaceHTMLPrimitives.commandButton(
              "×",
              testID: "browser-close-tab",
              commandID: "browser-tab-close:\(browser.activeTabID.uuidString)",
              classes: ["browser-tab-action", WorkspaceHTMLPrimitives.iconHitTargetClass],
              ariaLabel: "Close browser tab",
              disabled: !browser.canCloseActiveTab
          ))
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
