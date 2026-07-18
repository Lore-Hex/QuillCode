import Foundation

enum WorkspaceHTMLToolCardRenderer {
    static func render(_ card: ToolCardState, timelineItemID: String? = nil) -> String {
        let timelineAttribute = timelineItemID.map { #" data-timeline-id="\#(escape($0))""# } ?? ""
        let toolNameAttribute = #" data-tool-name="\#(escape(card.title))""#
        let displayTitle = WorkspaceToolDisplayNameBuilder.cardTitle(for: card.title)
        let executionContextAttribute = card.executionContext
            .map { #" data-execution-context="\#(escape($0.kind.rawValue))""# } ?? ""
        let accessibilityContext = card.executionContext
            .map { ", \($0.label) \($0.detail)" } ?? ""
        let copyID = timelineItemID ?? card.id
        return """
        <article class="tool-card \(card.status.rawValue)" data-testid="tool-card" data-status="\(card.status.rawValue)" data-review-state="\(card.reviewState.rawValue)" data-density="\(card.density.rawValue)" aria-label="\(escape(displayTitle)), \(escape(card.statusAccessibilityLabel)), \(escape(card.densityAccessibilityLabel))\(escape(accessibilityContext))"\(timelineAttribute)\(toolNameAttribute)\(executionContextAttribute)>
          <header>
            <span class="tool-card-title-row">
              <strong data-testid="tool-card-title">\(escape(displayTitle))</strong>
              \(WorkspaceHTMLPrimitives.executionContextChip(card.executionContext, testID: "tool-card-execution-context"))
            </span>
            <span data-testid="tool-card-status">\(escape(card.statusDisplayLabel))</span>
          </header>
          <p data-testid="tool-card-subtitle">\(escape(card.subtitle))</p>
          \(renderProgress(card.progress, status: card.status))
          \(renderActions(card.actions))
          \(renderTopLevelCopyAction(for: card, copyID: copyID))
          \(renderArtifacts(card.artifacts))
          \(renderTextPreviews(card.artifacts))
          \(renderDocumentPreviews(card.artifacts))
          \(renderImagePreviews(card.artifacts))
          \(renderDetails(card, copyID: copyID))
        </article>
        """
    }

    private static func renderProgress(_ progress: ToolProgressSurface?, status: ToolCardStatus) -> String {
        guard let progress, status == .running else { return "" }
        let valueAttributes: String
        let width: String
        if let fraction = progress.fractionCompleted {
            let percent = Int((fraction * 100).rounded())
            valueAttributes = #" aria-valuemin="0" aria-valuemax="100" aria-valuenow="\#(percent)""#
            width = "\(percent)%"
        } else {
            valueAttributes = ""
            width = "34%"
        }
        let label = progress.message ?? progress.percentLabel ?? "Tool in progress"
        return """
        <div class="tool-progress\(progress.fractionCompleted == nil ? " indeterminate" : "")" data-testid="tool-card-progress" role="progressbar" aria-label="\(escape(label))"\(valueAttributes)>
          <span style="width: \(width)"></span>
        </div>
        """
    }

    private static func renderTopLevelCopyAction(for card: ToolCardState, copyID: String) -> String {
        guard !showsDetailsCopyAction(for: card) else { return "" }
        return renderCopyAction(for: card, copyID: copyID)
    }

    private static func renderDetailsCopyAction(for card: ToolCardState, copyID: String) -> String {
        guard showsDetailsCopyAction(for: card) else { return "" }
        return renderCopyAction(for: card, copyID: copyID)
    }

    private static func renderCopyAction(for card: ToolCardState, copyID: String) -> String {
        """
        <footer class="transcript-actions">
          \(WorkspaceHTMLPrimitives.button(
              copyActionLabel(for: card),
              testID: "tool-card-copy",
              hitTargetKind: .text,
              attributes: [("data-copy-id", copyID)]
          ))
        </footer>
        """
    }

    private static func showsDetailsCopyAction(for card: ToolCardState) -> Bool {
        card.inputJSON != nil && card.outputJSON == nil
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

    private static func renderActions(_ actions: [ToolCardActionSurface]) -> String {
        guard !actions.isEmpty else { return "" }
        let buttons = actions.map { action in
            WorkspaceHTMLPrimitives.button(
                action.title,
                testID: "tool-card-action",
                hitTargetKind: .text,
                attributes: [
                    ("data-action-kind", action.kind.rawValue),
                    ("data-action-style", action.style.rawValue),
                    ("data-request-id", action.requestID)
                ]
            )
        }.joined(separator: "\n")
        return """
        <div class="tool-card-actions" data-testid="tool-card-actions">
          \(buttons)
        </div>
        """
    }

    private static func renderDetails(_ card: ToolCardState, copyID: String) -> String {
        guard card.inputJSON != nil || card.outputJSON != nil else { return "" }
        let isOpen = card.opensDetailsByDefault
        return """
        <details class="tool-details" data-testid="tool-card-details"\(isOpen ? " open" : "")>
          \(WorkspaceHTMLPrimitives.summaryContent(
              trustedHTML: detailsSummaryHTML(for: card, isOpen: isOpen),
              hitTargetKind: .row,
              classes: ["tool-details-summary"],
              ariaLabel: detailsLabel(for: card, isOpen: isOpen)
          ))
          \(card.inputJSON.map { #"<pre data-testid="tool-card-input">\#(escape($0))</pre>"# } ?? "")
          \(card.outputJSON.map { #"<pre data-testid="tool-card-output">\#(escape($0))</pre>"# } ?? "")
          \(renderDetailsCopyAction(for: card, copyID: copyID))
        </details>
        """
    }

    private static func detailsSummaryHTML(for card: ToolCardState, isOpen: Bool) -> String {
        let hint = !isOpen && card.status == .done
            ? #"<span class="tool-details-summary-hint">Raw tool data</span>"#
            : ""
        return """
        <span class="tool-details-summary-chevron" aria-hidden="true">›</span>
        <span class="tool-details-summary-label">\(escape(detailsLabel(for: card, isOpen: isOpen)))</span>
        \(hint)
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
            <a\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .link, classes: ["artifact-chip"])) data-testid="tool-card-artifact" data-kind="\(escape(artifact.kind.rawValue))"\(href)>
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
                #"<a\#(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .link)) data-testid="tool-card-document-preview-open" href="\#(escape($0))">Open</a>"#
            } ?? ""
            let pdfPreview = renderPDFPreview(artifact.pdfPreview)
            let officePreview = renderOfficePreview(artifact.officePreview)
            let tablePreview = renderTablePreview(artifact.tablePreview)
            let appshotPreview = renderAppshotPreview(artifact.appshotPreview)
            let archivePreview = renderArchivePreview(artifact.archivePreview)
            return """
            <figure class="artifact-document-preview" data-testid="tool-card-document-preview" data-kind="\(escape(preview.kind.rawValue))">
              <span class="artifact-document-icon" aria-hidden="true">\(documentIcon(for: preview.kind))</span>
              <figcaption>
                <small data-testid="tool-card-document-preview-type">\(escape(preview.typeLabel)) · \(escape(preview.extensionLabel))</small>
                <strong data-testid="tool-card-document-preview-label">\(escape(artifact.label))</strong>
                <small data-testid="tool-card-document-preview-detail">\(escape(preview.detail))</small>
              </figcaption>
              \(openLink)
              \(pdfPreview)
              \(officePreview)
              \(tablePreview)
              \(appshotPreview)
              \(archivePreview)
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
                <small data-testid="tool-card-image-preview-type">\(escape(preview.typeLine))</small>
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

    private static func renderOfficePreview(_ preview: ToolArtifactOfficePreview?) -> String {
        guard let preview else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-office-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-office-preview">
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderArchivePreview(_ preview: ToolArtifactArchivePreview?) -> String {
        guard let preview else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-archive-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-archive-preview">
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderPDFPreview(_ preview: ToolArtifactPDFPreview?) -> String {
        guard let preview else { return "" }
        let title = preview.title.map {
            #"<strong data-testid="tool-card-pdf-preview-title">\#(escape($0))</strong>"#
        } ?? ""
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-pdf-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !title.isEmpty || !metadata.isEmpty else {
            return ""
        }
        return """
        <div class="artifact-pdf-preview" data-testid="tool-card-pdf-preview">
          \(title)
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderTablePreview(_ preview: ToolArtifactTablePreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let headers = preview.headers.map {
            #"<th data-testid="tool-card-table-preview-header">\#(escape($0))</th>"#
        }.joined(separator: "")
        let rows = preview.rows.map { row in
            let cells = row.map {
                #"<td data-testid="tool-card-table-preview-cell">\#(escape($0))</td>"#
            }.joined(separator: "")
            return "<tr>\(cells)</tr>"
        }.joined(separator: "")
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-table-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        return """
        <div class="artifact-table-preview" data-testid="tool-card-table-preview">
          <div>
            \(metadata)
          </div>
          <table>
            <thead><tr>\(headers)</tr></thead>
            <tbody>\(rows)</tbody>
          </table>
        </div>
        """
    }

    private static func renderAppshotPreview(_ preview: ToolArtifactAppshotPreview?) -> String {
        guard let preview else { return "" }
        let image = preview.screenshotURL.map {
            #"<img class="artifact-appshot-image" data-testid="tool-card-appshot-preview-image" src="\#(escape($0))" alt="Appshot screenshot" loading="lazy">"#
        } ?? ""
        let title = preview.title.map {
            #"<strong data-testid="tool-card-appshot-preview-title">\#(escape($0))</strong>"#
        } ?? ""
        let summary = preview.summary.map {
            #"<small data-testid="tool-card-appshot-preview-summary">\#(escape($0))</small>"#
        } ?? ""
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-appshot-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !image.isEmpty || !title.isEmpty || !summary.isEmpty || !metadata.isEmpty else {
            return ""
        }
        return """
        <div class="artifact-appshot-preview" data-testid="tool-card-appshot-preview">
          \(image)
          <div>
            \(title)
            \(summary)
            \(metadata)
          </div>
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
        case .audio:
            return "AUD"
        case .video:
            return "VID"
        case .archive:
            return "ARC"
        }
    }

    private static func escape(_ text: String) -> String {
        WorkspaceHTMLPrimitives.escape(text)
    }
}
