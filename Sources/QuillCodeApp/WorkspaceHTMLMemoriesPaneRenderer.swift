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
        guard !memories.items.isEmpty else {
            return """
            <div class="memories-empty" data-testid="memories-empty">
              <strong>\(escape(memories.emptyTitle))</strong>
              <p>\(escape(memories.emptySubtitle))</p>
            </div>
            """
        }
        return """
        <div class="memories-grid" data-testid="memories-grid">
          \(memories.items.map(renderMemoryItem).joined(separator: "\n"))
        </div>
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
