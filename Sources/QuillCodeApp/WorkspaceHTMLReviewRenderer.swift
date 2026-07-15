import Foundation

enum WorkspaceHTMLReviewRenderer {
    static func render(_ review: WorkspaceReviewSurface) -> String {
        guard review.isVisible else { return "" }
        let pullRequestReviewDraft = renderPullRequestReviewDraft(review.pullRequestReviewDraft)
        let scope = review.activeScope ?? .unstaged
        let files = review.files.map { renderFile($0, scope: scope) }.joined(separator: "\n")
        let pullRequestThreads = renderPullRequestThreads(review.pullRequestThreads)
        return """
        <section class="review-pane" data-testid="review-pane" aria-label="Git review summary">
          <header>
            <strong>\(escape(review.title))</strong>
            <span data-testid="review-summary">\(escape(review.subtitle))</span>
            <small data-testid="review-badge">\(escape(review.badgeLabel))</small>
            \(WorkspaceHTMLPrimitives.commandButton(
                "Close",
                testID: "review-close",
                commandID: "toggle-review-panel",
                hitTargetKind: .icon,
                classes: ["review-close-button"],
                ariaLabel: "Close Review",
                title: "Close Review"
            ))
          </header>
          \(renderScopes(review))
          \(renderScopeNotice(review.scopeNotice))
          \(renderWholeDiffActions(review.wholeDiffActions))
          \(pullRequestReviewDraft)
          <ul>
            \(files)
          </ul>
          \(pullRequestThreads)
        </section>
        """
    }

    private static func renderScopeNotice(_ notice: String?) -> String {
        guard let notice else { return "" }
        return #"<p class="review-scope-notice" data-testid="review-scope-notice">\#(escape(notice))</p>"#
    }

    private static func renderWholeDiffActions(_ actions: [WorkspaceReviewActionSurface]) -> String {
        guard !actions.isEmpty else { return "" }
        return """
        <div class="review-header-actions" data-testid="review-header-actions">
          \(actions.map(renderAction).joined(separator: "\n"))
        </div>
        """
    }

    private static func renderScopes(_ review: WorkspaceReviewSurface) -> String {
        guard let activeScope = review.activeScope else { return "" }
        return """
        <div class="review-scopes" data-testid="review-scopes" role="group" aria-label="Review scope">
          \(review.availableScopes.map { scope in
              let isActive = scope == activeScope
              return """
              <button type="button"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .text, classes: ["review-scope-button"])) data-testid="review-scope" data-scope="\(escape(scope.rawValue))" aria-pressed="\(isActive ? "true" : "false")">
                \(escape(scope.title))
              </button>
              """
          }.joined(separator: "\n"))
        </div>
        """
    }

    private static func renderPullRequestReviewDraft(_ draft: WorkspacePullRequestReviewDraftSurface?) -> String {
        guard let draft else { return "" }
        let inlineComments = renderPullRequestReviewDraftInlineComments(draft)
        let submitSummary = renderPullRequestReviewDraftSubmitSummary(draft.submitSummary)
        return """
        <form class="pr-review-draft" data-testid="pr-review-draft" aria-label="Submit pull request review">
          <label>
            Action
            <select\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) data-testid="pr-review-draft-action" aria-label="Pull request review action">
              \(WorkspacePullRequestReviewActionKind.allCases.map { action in
                  let selected = action == draft.action ? #" selected="selected""# : ""
                  return #"<option value="\#(escape(action.rawValue))"\#(selected)>\#(escape(action.title))</option>"#
              }.joined(separator: "\n"))
            </select>
          </label>
          <label>
            Pull request
            <input\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) data-testid="pr-review-draft-selector" aria-label="Pull request selector" placeholder="PR number, URL, or branch" value="\(escape(draft.selector))">
          </label>
          <label>
            Body
            <textarea\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) data-testid="pr-review-draft-body" aria-label="Pull request review body" placeholder="\(escape(draft.action.bodyPlaceholder))">\(escape(draft.body))</textarea>
          </label>
          \(inlineComments)
          \(submitSummary)
          <footer>
            <button type="reset"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .formAction, classes: ["review-action-button"])) data-testid="pr-review-draft-cancel">Cancel</button>
            <button type="submit"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .formAction, classes: ["review-action-button"])) data-testid="pr-review-draft-submit"\(draft.canSubmit ? "" : " disabled")>\(escape(submitTitle(for: draft.action)))</button>
          </footer>
        </form>
        """
    }

    private static func renderPullRequestReviewDraftSubmitSummary(
        _ summary: WorkspacePullRequestReviewDraftSubmitSummarySurface
    ) -> String {
        """
        <section class="pr-review-draft-summary" data-testid="pr-review-draft-summary" data-status="\(escape(summary.status.rawValue))" aria-label="Pull request review submit summary">
          <strong data-testid="pr-review-draft-summary-title">\(escape(summary.title))</strong>
          <p data-testid="pr-review-draft-summary-detail">\(escape(summary.detail))</p>
          <ul>
            \(summary.items.map { #"<li data-testid="pr-review-draft-summary-item">\#(escape($0))</li>"# }.joined(separator: "\n"))
          </ul>
        </section>
        """
    }

    private static func renderPullRequestReviewDraftInlineComments(
        _ draft: WorkspacePullRequestReviewDraftSurface
    ) -> String {
        guard draft.inlineCommentCount > 0 else { return "" }
        let checked = draft.includeInlineComments ? #" checked="checked""# : ""
        let comments = draft.inlineComments.enumerated().map { index, comment in
            let commentChecked = comment.isIncluded ? #" checked="checked""# : ""
            let disabled = draft.includeInlineComments ? "" : " disabled"
            let moveUpDisabled = !draft.includeInlineComments || index == 0
            let moveDownDisabled = !draft.includeInlineComments || index >= draft.inlineComments.count - 1
            return """
            <li data-testid="pr-review-draft-inline-comment">
              <label>
                <input\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .icon)) type="checkbox" data-testid="pr-review-draft-inline-comment-toggle" aria-label="Include inline note at \(escape(comment.locationLabel))" data-comment-id="\(escape(comment.id.uuidString))"\(commentChecked)\(disabled)>
                <span>\(comment.isIncluded ? "Included" : "Skipped")</span>
              </label>
              <span class="pr-review-inline-comment-order">
                <button type="button"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .icon, classes: ["review-action-button"])) data-testid="pr-review-draft-inline-comment-move-up" aria-label="Move inline note at \(escape(comment.locationLabel)) up" data-comment-id="\(escape(comment.id.uuidString))"\(moveUpDisabled ? " disabled" : "")>^</button>
                <button type="button"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .icon, classes: ["review-action-button"])) data-testid="pr-review-draft-inline-comment-move-down" aria-label="Move inline note at \(escape(comment.locationLabel)) down" data-comment-id="\(escape(comment.id.uuidString))"\(moveDownDisabled ? " disabled" : "")>v</button>
              </span>
              <code>\(escape(comment.locationLabel))</code>
              <textarea\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) data-testid="pr-review-draft-inline-comment-body" aria-label="Inline note text at \(escape(comment.locationLabel))" data-comment-id="\(escape(comment.id.uuidString))">\(escape(comment.body))</textarea>
              \(draft.includeInlineComments && comment.isIncluded && comment.normalizedBody.isEmpty ? #"<small data-testid="pr-review-draft-inline-comment-warning">Add note text or skip this note.</small>"# : "")
            </li>
            """
        }.joined(separator: "\n")
        let selectedCount = draft.selectedInlineCommentCount
        let countLabel = selectedCount == draft.inlineCommentCount
            ? "\(draft.inlineCommentCount) inline review note\(draft.inlineCommentCount == 1 ? "" : "s")"
            : "\(selectedCount) of \(draft.inlineCommentCount) inline review notes"
        return """
        <label class="pr-review-inline-comments">
          <input\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .icon)) type="checkbox" data-testid="pr-review-draft-include-inline-comments" aria-label="Include inline review notes"\(checked)>
          <span>Include \(countLabel)</span>
        </label>
        <ul class="pr-review-inline-comment-list" data-testid="pr-review-draft-inline-comments">
          \(comments)
        </ul>
        """
    }

    private static func submitTitle(for action: WorkspacePullRequestReviewActionKind) -> String {
        switch action {
        case .approve:
            return "Submit approval"
        case .comment:
            return "Submit comment"
        case .requestChanges:
            return "Request changes"
        }
    }

    private static func renderFile(
        _ file: WorkspaceReviewFileSurface,
        scope: WorkspaceReviewScope
    ) -> String {
        let comments = file.comments.map { comment in
            """
            <blockquote data-testid="review-comment">\(escape(comment.text))</blockquote>
            """
        }.joined(separator: "\n")
        let unreadable = file.unreadableReason.map {
            #"<small data-testid="review-file-unreadable">\#(escape($0))</small>"#
        } ?? ""
        return """
        <li data-testid="review-file">
          <span data-testid="review-file-path">\(escape(file.path))</span>
          <small>\(escape(file.changeLabel))</small>
          <span>
            \(file.actions(in: scope).map(renderAction).joined(separator: "\n"))
          </span>
          \(unreadable)
          \(file.hunkItems.map { renderHunk($0, scope: scope) }.joined(separator: "\n"))
          \(comments)
        </li>
        """
    }

    private static func renderHunk(
        _ hunk: WorkspaceReviewHunkSurface,
        scope: WorkspaceReviewScope
    ) -> String {
        """
        <div data-testid="review-hunk">
          <code data-testid="review-hunk-header">\(escape(hunk.header))</code>
          <small>\(escape(hunk.changeLabel))</small>
          <span>
            \(hunk.actions(in: scope).map(renderAction).joined(separator: "\n"))
          </span>
          <ol data-testid="review-lines">
            \(hunk.lines.map(renderLine).joined(separator: "\n"))
          </ol>
        </div>
        """
    }

    private static func renderLine(_ line: WorkspaceReviewLineSurface) -> String {
        let comments = line.comments.map { comment in
            let rangeLabel = comment.lineRangeLabel
                .map { "<strong>\(escape($0))</strong> " } ?? ""
            return """
            <blockquote data-testid="review-line-comment">\(rangeLabel)\(escape(comment.text))</blockquote>
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

    private static func renderAction(_ action: WorkspaceReviewActionSurface) -> String {
        """
        <button type="button"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .text, classes: ["review-action-button"])) data-testid="review-action" data-action="\(escape(action.kind.rawValue))" data-path="\(escape(action.path))">
          \(escape(action.kind.title))
        </button>
        """
    }

    private static func renderPullRequestThreads(_ threads: [WorkspacePullRequestReviewThreadSurface]) -> String {
        guard !threads.isEmpty else { return "" }
        return """
        <section class="pr-review-threads" data-testid="pr-review-threads" aria-label="Pull request review threads">
          <strong>Pull request review threads</strong>
          <ul>
            \(threads.map(renderPullRequestThread).joined(separator: "\n"))
          </ul>
        </section>
        """
    }

    private static func renderPullRequestThread(_ thread: WorkspacePullRequestReviewThreadSurface) -> String {
        """
        <li data-testid="pr-review-thread" data-thread-id="\(escape(thread.id))">
          <span data-testid="pr-review-thread-status">\(escape(thread.statusLabel))</span>
          <code data-testid="pr-review-thread-location">\(escape(thread.locationLabel))</code>
          <blockquote data-testid="pr-review-thread-comment">\(escape(thread.summaryText))</blockquote>
          <span>
            \(renderPullRequestThreadReply(thread))
            \(thread.actions.map(renderPullRequestThreadAction).joined(separator: "\n"))
          </span>
        </li>
        """
    }

    private static func renderPullRequestThreadReply(_ thread: WorkspacePullRequestReviewThreadSurface) -> String {
        guard let replyTarget = thread.replyTarget else { return "" }
        let selectorAttribute = replyTarget.selector.map { #" data-selector="\#(escape($0))""# } ?? ""
        return """
        <button type="button"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .text, classes: ["review-action-button"])) data-testid="pr-review-thread-reply" data-thread-id="\(escape(replyTarget.threadID))">
          Reply
        </button>
        <form class="pr-review-thread-reply-form" data-testid="pr-review-thread-reply-form" data-thread-id="\(escape(replyTarget.threadID))" data-comment-id="\(replyTarget.commentID)"\(selectorAttribute) hidden>
          <textarea\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .textEntry)) data-testid="pr-review-thread-reply-input" aria-label="Reply to review thread" placeholder="Reply to review thread"></textarea>
          <button type="reset"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .formAction, classes: ["review-action-button"])) data-testid="pr-review-thread-reply-cancel">Cancel</button>
          <button type="submit"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .formAction, classes: ["review-action-button"])) data-testid="pr-review-thread-reply-submit">Post reply</button>
        </form>
        """
    }

    private static func renderPullRequestThreadAction(
        _ action: WorkspacePullRequestReviewThreadActionSurface
    ) -> String {
        """
        <button type="button"\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .text, classes: ["review-action-button"])) data-testid="pr-review-thread-action" data-action="\(escape(action.kind.rawValue))" data-thread-id="\(escape(action.threadID))">
          \(escape(action.kind.title))
        </button>
        """
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
