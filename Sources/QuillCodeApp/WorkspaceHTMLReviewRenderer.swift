import Foundation

enum WorkspaceHTMLReviewRenderer {
    static func render(_ review: WorkspaceReviewSurface) -> String {
        guard review.isVisible else { return "" }
        let files = review.files.map(renderFile).joined(separator: "\n")
        return """
        <section class="review-pane" data-testid="review-pane" aria-label="Git review summary">
          <header>
            <strong>\(escape(review.title))</strong>
            <span data-testid="review-summary">\(escape(review.subtitle))</span>
          </header>
          <ul>
            \(files)
          </ul>
        </section>
        """
    }

    private static func renderFile(_ file: WorkspaceReviewFileSurface) -> String {
        let comments = file.comments.map { comment in
            """
            <blockquote data-testid="review-comment">\(escape(comment.text))</blockquote>
            """
        }.joined(separator: "\n")
        return """
        <li data-testid="review-file">
          <span data-testid="review-file-path">\(escape(file.path))</span>
          <small>\(escape(file.changeLabel))</small>
          <span>
            \(file.actions.map(renderAction).joined(separator: "\n"))
          </span>
          \(file.hunkItems.map(renderHunk).joined(separator: "\n"))
          \(comments)
        </li>
        """
    }

    private static func renderHunk(_ hunk: WorkspaceReviewHunkSurface) -> String {
        """
        <div data-testid="review-hunk">
          <code data-testid="review-hunk-header">\(escape(hunk.header))</code>
          <small>\(escape(hunk.changeLabel))</small>
          <span>
            \(hunk.actions.map(renderAction).joined(separator: "\n"))
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
        <button type="button" class="review-action-button \(WorkspaceHTMLPrimitives.textHitTargetClass)" data-testid="review-action" data-action="\(escape(action.kind.rawValue))" data-path="\(escape(action.path))">
          \(escape(action.kind.title))
        </button>
        """
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
