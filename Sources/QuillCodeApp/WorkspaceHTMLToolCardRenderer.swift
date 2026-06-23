import Foundation

enum WorkspaceHTMLToolCardRenderer {
    static func render(_ card: ToolCardState, timelineItemID: String? = nil) -> String {
        let timelineAttribute = timelineItemID.map { #" data-timeline-id="\#(escape($0))""# } ?? ""
        let executionContextAttribute = card.executionContext
            .map { #" data-execution-context="\#(escape($0.kind.rawValue))""# } ?? ""
        let accessibilityContext = card.executionContext
            .map { ", \($0.label) \($0.detail)" } ?? ""
        let copyID = timelineItemID ?? card.id
        return """
        <article class="tool-card \(card.status.rawValue)" data-testid="tool-card" data-status="\(card.status.rawValue)" data-density="\(card.density.rawValue)" aria-label="\(escape(card.title)), \(escape(card.status.rawValue)), \(escape(card.densityAccessibilityLabel))\(escape(accessibilityContext))"\(timelineAttribute)\(executionContextAttribute)>
          <header>
            <span class="tool-card-title-row">
              <strong data-testid="tool-card-title">\(escape(card.title))</strong>
              \(WorkspaceHTMLPrimitives.executionContextChip(card.executionContext, testID: "tool-card-execution-context"))
            </span>
            <span data-testid="tool-card-status">\(escape(card.status.rawValue))</span>
          </header>
          <p data-testid="tool-card-subtitle">\(escape(card.subtitle))</p>
          <footer class="transcript-actions">
            <button type="button" data-testid="tool-card-copy" data-copy-id="\(escape(copyID))">\(escape(copyActionLabel(for: card)))</button>
          </footer>
          \(renderArtifacts(card.artifacts))
          \(renderTextPreviews(card.artifacts))
          \(renderDocumentPreviews(card.artifacts))
          \(renderImagePreviews(card.artifacts))
          \(renderDetails(card))
        </article>
        """
    }

    private static func copyActionLabel(for card: ToolCardState) -> String {
        if card.outputJSON != nil {
            return "Copy output"
        }
        if card.inputJSON != nil {
            return "Copy input"
        }
        return "Copy"
    }

    private static func renderDetails(_ card: ToolCardState) -> String {
        guard card.inputJSON != nil || card.outputJSON != nil else { return "" }
        let isOpen = card.opensDetailsByDefault
        return """
        <details data-testid="tool-card-details"\(isOpen ? " open" : "")>
          <summary>\(detailsLabel(for: card, isOpen: isOpen))</summary>
          \(card.inputJSON.map { #"<pre data-testid="tool-card-input">\#(escape($0))</pre>"# } ?? "")
          \(card.outputJSON.map { #"<pre data-testid="tool-card-output">\#(escape($0))</pre>"# } ?? "")
        </details>
        """
    }

    private static func detailsLabel(for card: ToolCardState, isOpen: Bool) -> String {
        if isOpen {
            return "Hide details"
        }
        switch (card.inputJSON != nil, card.outputJSON != nil) {
        case (true, true):
            return "Show details"
        case (true, false):
            return "Show input"
        case (false, true):
            return "Show output"
        case (false, false):
            return "Show details"
        }
    }

    private static func renderArtifacts(_ artifacts: [ToolArtifactState]) -> String {
        guard !artifacts.isEmpty else { return "" }
        let chips = artifacts.map { artifact in
            let href = artifact.href.map { #" href="\#(escape($0))""# } ?? ""
            return """
            <a class="artifact-chip" data-testid="tool-card-artifact" data-kind="\(escape(artifact.kind.rawValue))"\(href)>
              <strong data-testid="tool-card-artifact-label">\(escape(artifact.label))</strong>
              <small data-testid="tool-card-artifact-detail">\(escape(artifact.detail))</small>
            </a>
            """
        }.joined(separator: "\n")
        return """
        <div class="tool-artifacts" data-testid="tool-card-artifacts" aria-label="Artifacts">
          \(chips)
        </div>
        """
    }

    private static func renderTextPreviews(_ artifacts: [ToolArtifactState]) -> String {
        let textArtifacts = artifacts.filter(\.hasTextPreview)
        guard !textArtifacts.isEmpty else { return "" }
        let previews = textArtifacts.map { artifact in
            """
            <figure class="artifact-text-preview" data-testid="tool-card-text-preview">
              <figcaption data-testid="tool-card-text-preview-label">\(escape(artifact.label))</figcaption>
              <pre data-testid="tool-card-text-preview-content">\(escape(artifact.textPreview ?? ""))</pre>
            </figure>
            """
        }.joined(separator: "\n")
        return """
        <div class="tool-artifact-text-previews" data-testid="tool-card-text-previews" aria-label="Text previews">
          \(previews)
        </div>
        """
    }

    private static func renderDocumentPreviews(_ artifacts: [ToolArtifactState]) -> String {
        let documentArtifacts = artifacts.filter(\.isDocumentPreview)
        guard !documentArtifacts.isEmpty else { return "" }
        let previews = documentArtifacts.compactMap { artifact -> String? in
            guard let preview = artifact.documentPreview else { return nil }
            let openLink = artifact.href.map {
                #"<a data-testid="tool-card-document-preview-open" href="\#(escape($0))">Open</a>"#
            } ?? ""
            return """
            <figure class="artifact-document-preview" data-testid="tool-card-document-preview" data-kind="\(escape(preview.kind.rawValue))">
              <span class="artifact-document-icon" aria-hidden="true">\(documentIcon(for: preview.kind))</span>
              <figcaption>
                <small data-testid="tool-card-document-preview-type">\(escape(preview.typeLabel)) · \(escape(preview.extensionLabel))</small>
                <strong data-testid="tool-card-document-preview-label">\(escape(artifact.label))</strong>
                <small data-testid="tool-card-document-preview-detail">\(escape(preview.detail))</small>
              </figcaption>
              \(openLink)
            </figure>
            """
        }.joined(separator: "\n")
        guard !previews.isEmpty else { return "" }
        return """
        <div class="tool-artifact-document-previews" data-testid="tool-card-document-previews" aria-label="Document previews">
          \(previews)
        </div>
        """
    }

    private static func renderImagePreviews(_ artifacts: [ToolArtifactState]) -> String {
        let imageArtifacts = artifacts.filter(\.isImagePreview)
        guard !imageArtifacts.isEmpty else { return "" }
        let previews = imageArtifacts.compactMap { artifact -> String? in
            guard let src = artifact.previewURL,
                  let preview = artifact.imagePreview
            else { return nil }
            return """
            <figure class="artifact-preview" data-testid="tool-card-image-preview" data-kind="image">
              <img src="\(escape(src))" alt="\(escape(artifact.label))" loading="lazy">
              <figcaption>
                <small data-testid="tool-card-image-preview-type">\(escape(preview.typeLabel)) · \(escape(preview.extensionLabel))</small>
                <strong data-testid="tool-card-image-preview-label">\(escape(artifact.label))</strong>
                <small data-testid="tool-card-image-preview-detail">\(escape(preview.detail))</small>
              </figcaption>
            </figure>
            """
        }.joined(separator: "\n")
        guard !previews.isEmpty else { return "" }
        return """
        <div class="tool-artifact-previews" data-testid="tool-card-image-previews" aria-label="Image previews">
          \(previews)
        </div>
        """
    }

    private static func documentIcon(for kind: ToolArtifactDocumentKind) -> String {
        switch kind {
        case .appshot:
            return "APP"
        case .pdf:
            return "PDF"
        case .document:
            return "DOC"
        case .spreadsheet:
            return "XLS"
        case .presentation:
            return "PPT"
        }
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
