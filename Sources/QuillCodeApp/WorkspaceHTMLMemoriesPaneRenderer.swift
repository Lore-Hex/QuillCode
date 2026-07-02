enum WorkspaceHTMLMemoriesPaneRenderer {
    private typealias Primitives = WorkspaceHTMLSecondaryPanePrimitives

    static func render(_ memories: WorkspaceMemoriesSurface) -> String {
        guard memories.isVisible else { return "" }
        let content = renderContent(memories)
        return """
        <section class="memories-pane" data-testid="memories-pane" aria-label="QuillCode memories">
          <header>
            <div>
              <strong>\(escape(memories.title))</strong>
              <p data-testid="memories-subtitle">\(escape(memories.subtitle))</p>
            </div>
            <span class="memories-counts">
              \(renderCounts(memories))
            </span>
          </header>
          \(content)
        </section>
        """
    }

    private static func renderContent(_ memories: WorkspaceMemoriesSurface) -> String {
        guard !memories.items.isEmpty || !memories.redactionReviews.isEmpty else {
            return """
            <div class="memories-empty" data-testid="memories-empty">
              <strong>\(escape(memories.emptyTitle))</strong>
              <p>\(escape(memories.emptySubtitle))</p>
            </div>
            """
        }
        return """
        <div class="memories-grid" data-testid="memories-grid">
          \(renderRedactionReviews(memories))
          \(renderConflicts(memories))
          \(memories.items.map(renderMemoryItem).joined(separator: "\n"))
        </div>
        """
    }

    private static func renderRedactionReviews(_ memories: WorkspaceMemoriesSurface) -> String {
        guard !memories.redactionReviews.isEmpty else { return "" }
        return memories.redactionReviews.map(renderRedactionReview).joined(separator: "\n")
    }

    private static func renderRedactionReview(_ review: MemoryRedactionReviewSurface) -> String {
        """
        <article class="memory-redaction-card" data-testid="memory-redaction-review">
          <header>
            <strong data-testid="memory-redaction-title">\(escape(review.title))</strong>
            \(renderCommand(
                "Add safe memory",
                testID: "memory-redaction-add",
                commandID: review.addCommandID,
                classes: ["memory-redaction-add-button"]
            ))
          </header>
          <p data-testid="memory-redaction-summary">\(escape(review.summary))</p>
          <code data-testid="memory-redaction-input">\(escape(review.redactedInput))</code>
          <small data-testid="memory-redaction-guidance">\(escape(review.guidance))</small>
        </article>
        """
    }

    private static func renderConflicts(_ memories: WorkspaceMemoriesSurface) -> String {
        guard !memories.conflicts.isEmpty else { return "" }
        return memories.conflicts.map(renderConflict).joined(separator: "\n")
    }

    private static func renderConflict(_ conflict: MemoryConflictSurface) -> String {
        """
        <article class="memory-conflict-card" data-testid="memory-conflict">
          <header>
            <strong data-testid="memory-conflict-title">\(escape(conflict.title))</strong>
          </header>
          <p data-testid="memory-conflict-summary">\(escape(conflict.summary))</p>
          <div class="memory-conflict-sides">
            \(renderConflictSide(conflict.global))
            \(renderConflictSide(conflict.project))
          </div>
        </article>
        """
    }

    private static func renderConflictSide(_ side: MemoryConflictSideSurface) -> String {
        """
        <section class="memory-conflict-side">
          <strong>\(escape(side.scopeLabel))</strong>
          <span>\(escape(side.title))</span>
          <code>\(escape(side.relativePath))</code>
          \(renderCommand(
              "Edit \(side.scopeLabel.lowercased())",
              testID: "memory-conflict-edit",
              commandID: side.editCommandID,
              classes: ["memory-conflict-edit-button"]
          ))
        </section>
        """
    }

    private static func renderCounts(_ memories: WorkspaceMemoriesSurface) -> String {
        [
            countChip(memories.globalCount, singular: "global memory"),
            countChip(memories.projectCount, singular: "project memory")
        ].joined(separator: "\n")
    }

    private static func countChip(_ count: Int, singular: String) -> String {
        #"<span data-testid="memories-count">\#(Primitives.countLabel(count, singular: singular))</span>"#
    }

    private static func renderMemoryItem(_ item: MemoryNoteSurface) -> String {
        let editButton = renderCommand(
            "Edit",
            testID: "memory-edit",
            commandID: item.editCommandID,
            classes: ["memory-edit-button"]
        )
        let deleteButton = renderCommand(
            "Forget",
            testID: "memory-delete",
            commandID: item.deleteCommandID,
            classes: ["memory-delete-button"]
        )
        return """
        <article class="memory-card" data-testid="memory-item" data-scope="\(escape(item.scope.rawValue))">
          <header>
            <span data-testid="memory-scope">\(escape(item.scopeLabel))</span>
            <span data-testid="memory-size">\(escape(item.byteCountLabel))</span>
            \(editButton)
            \(deleteButton)
          </header>
          <strong data-testid="memory-title">\(escape(item.title))</strong>
          <p data-testid="memory-preview">\(escape(item.preview))</p>
          <code data-testid="memory-path">\(escape(item.relativePath))</code>
        </article>
        """
    }

    private static func renderCommand(
        _ label: String,
        testID: String,
        commandID: String?,
        classes: [String]
    ) -> String {
        guard let commandID else { return "" }
        return Primitives.commandButton(
            label,
            testID: testID,
            commandID: commandID,
            hitTargetKind: .formAction,
            classes: classes
        )
    }

    private static func escape(_ text: String) -> String {
        Primitives.escape(text)
    }
}
