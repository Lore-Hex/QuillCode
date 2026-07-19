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
            let metadata = artifact.sourceTextPreview?.metadataLines.map {
                #"<small data-testid="tool-card-text-preview-meta">\#(escape($0))</small>"#
            }.joined(separator: "\n") ?? ""
            return """
            <figure class="artifact-text-preview" data-testid="tool-card-text-preview">
              <figcaption data-testid="tool-card-text-preview-label">\(escape(artifact.label))</figcaption>
              <div class="artifact-text-preview-meta" data-testid="tool-card-text-preview-metadata">
                \(metadata)
              </div>
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
            let pdfPreview = renderPDFPreview(artifact.pdfPreview, href: artifact.href)
            let markdownPreview = renderMarkdownPreview(artifact.markdownPreview)
            let officePreview = renderOfficePreview(artifact.officePreview)
            let rtfPreview = renderRTFPreview(artifact.rtfPreview)
            let htmlPreview = renderHTMLPreview(artifact.htmlPreview)
            let diffPreview = renderDiffPreview(artifact.diffPreview)
            let tablePreview = renderTablePreview(artifact.tablePreview)
            let istanbulPreviewModel = artifact.istanbulPreview
            let istanbulPreview = renderIstanbulPreview(istanbulPreviewModel)
            let coveragePyPreviewModel = artifact.coveragePyPreview
            let coveragePyPreview = renderCoveragePyPreview(coveragePyPreviewModel)
            let pytestJSONPreviewModel = artifact.pytestJSONPreview
            let pytestJSONPreview = renderPytestJSONPreview(pytestJSONPreviewModel)
            let jestJSONPreviewModel = artifact.jestJSONPreview
            let jestJSONPreview = renderJestJSONPreview(jestJSONPreviewModel)
            let tapPreview = renderTAPPreview(artifact.tapPreview)
            let harPreview = renderHARPreview(artifact.harPreview)
            let lcovPreview = renderLCOVPreview(artifact.lcovPreview)
            let goCoveragePreview = renderGoCoveragePreview(artifact.goCoveragePreview)
            let sarifPreview = renderSARIFPreview(artifact.sarifPreview)
            let jsonLinesPreview = renderJSONLinesPreview(artifact.jsonLinesPreview)
            let tomlPreview = renderTOMLPreview(artifact.tomlPreview)
            let iniPreview = renderINIPreview(artifact.iniPreview)
            let dotenvPreview = renderDotenvPreview(artifact.dotenvPreview)
            let yamlPreview = renderYAMLPreview(artifact.yamlPreview)
            let junitPreviewModel = artifact.junitPreview
            let junitPreview = renderJUnitPreview(junitPreviewModel)
            let trxPreview = renderTRXPreview(artifact.trxPreview)
            let xunitPreviewModel = artifact.xunitPreview
            let xunitPreview = renderXUnitPreview(xunitPreviewModel)
            let nunitPreviewModel = artifact.nunitPreview
            let nunitPreview = renderNUnitPreview(nunitPreviewModel)
            let coberturaPreviewModel = artifact.coberturaPreview
            let coberturaPreview = renderCoberturaPreview(coberturaPreviewModel)
            let cloverPreviewModel = artifact.cloverPreview
            let cloverPreview = renderCloverPreview(cloverPreviewModel)
            let jaCoCoPreviewModel = artifact.jaCoCoPreview
            let jaCoCoPreview = renderJaCoCoPreview(jaCoCoPreviewModel)
            let xmlPreview = junitPreviewModel == nil
                && xunitPreviewModel == nil
                && nunitPreviewModel == nil
                && coberturaPreviewModel == nil
                && cloverPreviewModel == nil
                && jaCoCoPreviewModel == nil
                ? renderXMLPreview(artifact.xmlPreview)
                : ""
            let propertyListPreview = renderPropertyListPreview(artifact.propertyListPreview)
            let sqlitePreview = renderSQLitePreview(artifact.sqlitePreview)
            let webAssemblyPreview = renderWebAssemblyPreview(artifact.webAssemblyPreview)
            let fontPreview = renderFontPreview(artifact.fontPreview)
            let executablePreview = renderExecutablePreview(artifact.executablePreview)
            let notebookPreview = renderNotebookPreview(artifact.notebookPreview)
            let jsonPreview = istanbulPreviewModel == nil
                && coveragePyPreviewModel == nil
                && pytestJSONPreviewModel == nil
                && jestJSONPreviewModel == nil
                ? renderJSONPreview(artifact.jsonPreview)
                : ""
            let appshotPreview = renderAppshotPreview(artifact.appshotPreview)
            let archivePreview = renderArchivePreview(artifact.archivePreview)
            let mediaPreview = renderMediaPreview(artifact.mediaPreview)
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
              \(markdownPreview)
              \(officePreview)
              \(rtfPreview)
              \(htmlPreview)
              \(diffPreview)
              \(tablePreview)
              \(istanbulPreview)
              \(coveragePyPreview)
              \(pytestJSONPreview)
              \(jestJSONPreview)
              \(tapPreview)
              \(harPreview)
              \(lcovPreview)
              \(goCoveragePreview)
              \(sarifPreview)
              \(jsonLinesPreview)
              \(tomlPreview)
              \(iniPreview)
              \(dotenvPreview)
              \(yamlPreview)
              \(junitPreview)
              \(trxPreview)
              \(xunitPreview)
              \(nunitPreview)
              \(coberturaPreview)
              \(cloverPreview)
              \(jaCoCoPreview)
              \(xmlPreview)
              \(propertyListPreview)
              \(sqlitePreview)
              \(webAssemblyPreview)
              \(fontPreview)
              \(executablePreview)
              \(notebookPreview)
              \(jsonPreview)
              \(appshotPreview)
              \(archivePreview)
              \(mediaPreview)
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
        let previews = imageArtifacts.enumerated().compactMap { index, artifact -> String? in
            guard let src = artifact.previewURL,
                  let preview = artifact.imagePreview
            else { return nil }
            let sequenceLabel = imageArtifacts.count > 1
                ? #"<small data-testid="tool-card-image-preview-sequence">Image \#(index + 1) of \#(imageArtifacts.count)</small>"#
                : ""
            return """
            <figure class="artifact-preview" data-testid="tool-card-image-preview" data-kind="image">
              <img src="\(escape(src))" alt="\(escape(artifact.label))" loading="lazy">
              <figcaption>
                <small data-testid="tool-card-image-preview-type">\(escape(preview.typeLine))</small>
                \(sequenceLabel)
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
        let contents = preview.contentPreviewLabels.map {
            #"<li data-testid="tool-card-office-preview-content-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let contentList = contents.isEmpty
            ? ""
            : """
              <section class="artifact-office-contents" data-testid="tool-card-office-preview-contents">
                <strong data-testid="tool-card-office-preview-content-title">Contents</strong>
                <ul>\(contents)</ul>
              </section>
            """
        guard !metadata.isEmpty || !contentList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-office-preview">
          <div>
            \(metadata)
          </div>
          \(contentList)
        </div>
        """
    }

    private static func renderRTFPreview(_ preview: ToolArtifactRTFPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let title = preview.title.map {
            #"<strong data-testid="tool-card-rtf-preview-title">\#(escape($0))</strong>"#
        } ?? ""
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-rtf-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !title.isEmpty || !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-rtf-preview">
          \(title)
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderHTMLPreview(_ preview: ToolArtifactHTMLPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let title = (preview.title ?? preview.heading).map {
            #"<strong data-testid="tool-card-html-preview-title">\#(escape($0))</strong>"#
        } ?? ""
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-html-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !title.isEmpty || !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-html-preview">
          \(title)
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderDiffPreview(_ preview: ToolArtifactDiffPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-diff-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let changedFiles = preview.changedFileLabels.map {
            #"<li data-testid="tool-card-diff-preview-file-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let changedFileList = changedFiles.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-diff-preview-files">
                <strong data-testid="tool-card-diff-preview-file-title">Changed files</strong>
                <ul>\(changedFiles)</ul>
              </section>
        """
        guard !metadata.isEmpty || !changedFileList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-diff-preview">
          <div>
            \(metadata)
          </div>
          \(changedFileList)
        </div>
        """
    }

    private static func renderMarkdownPreview(_ preview: ToolArtifactMarkdownPreview?) -> String {
        guard let preview else { return "" }
        let title = preview.title.map {
            #"<strong data-testid="tool-card-markdown-preview-title">\#(escape($0))</strong>"#
        } ?? ""
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-markdown-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !title.isEmpty || !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-markdown-preview" data-testid="tool-card-markdown-preview">
          \(title)
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
        let contents = preview.entryPreviewLabels.map {
            #"<li data-testid="tool-card-archive-preview-entry-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let contentList = contents.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-archive-preview-entries">
                <strong data-testid="tool-card-archive-preview-entry-title">Contents</strong>
                <ul>\(contents)</ul>
              </section>
        """
        guard !metadata.isEmpty || !contentList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-archive-preview">
          <div>
            \(metadata)
          </div>
          \(contentList)
        </div>
        """
    }

    private static func renderMediaPreview(_ preview: ToolArtifactMediaPreview?) -> String {
        guard let preview else { return "" }
        let title = preview.title.map {
            #"<strong data-testid="tool-card-media-preview-title">\#(escape($0))</strong>"#
        } ?? ""
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-media-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let player = renderMediaPlayer(preview)
        guard !title.isEmpty || !metadata.isEmpty || !player.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-media-preview">
          \(title)
          <div>
            \(metadata)
          </div>
          \(player)
        </div>
        """
    }

    private static func renderMediaPlayer(_ preview: ToolArtifactMediaPreview) -> String {
        guard let playbackURL = preview.playbackURL else { return "" }
        switch preview.kind {
        case .audio:
            return #"<audio class="artifact-media-player" data-testid="tool-card-media-player" controls preload="metadata" src="\#(escape(playbackURL))"></audio>"#
        case .video:
            return #"<video class="artifact-media-player" data-testid="tool-card-media-player" controls preload="metadata" src="\#(escape(playbackURL))"></video>"#
        default:
            return ""
        }
    }

    private static func renderPDFPreview(_ preview: ToolArtifactPDFPreview?, href: String?) -> String {
        guard let preview else { return "" }
        let title = preview.title.map {
            #"<strong data-testid="tool-card-pdf-preview-title">\#(escape($0))</strong>"#
        } ?? ""
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-pdf-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let pagePreview = renderLocalPDFPagePreview(href: href)
        guard !title.isEmpty || !metadata.isEmpty || !pagePreview.isEmpty else {
            return ""
        }
        return """
        <div class="artifact-pdf-preview" data-testid="tool-card-pdf-preview">
          \(title)
          <div>
            \(metadata)
          </div>
          \(pagePreview)
        </div>
        """
    }

    private static func renderLocalPDFPagePreview(href: String?) -> String {
        guard let href,
              let url = URL(string: href),
              url.isFileURL
        else { return "" }
        return """
        <object class="artifact-pdf-page-preview" data-testid="tool-card-pdf-page-preview" type="application/pdf" data="\(escape(href))#page=1">
          <a\(WorkspaceHTMLPrimitives.hitTargetAttributes(kind: .link)) data-testid="tool-card-pdf-page-preview-fallback" href="\(escape(href))">Open PDF preview</a>
        </object>
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

    private static func renderJSONPreview(_ preview: ToolArtifactJSONPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-json-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let keys = preview.keyPreviewLabels.map {
            #"<li data-testid="tool-card-json-preview-key-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let keyList = keys.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-json-preview-keys">
                <strong data-testid="tool-card-json-preview-key-title">Top keys</strong>
                <ul>\(keys)</ul>
              </section>
        """
        guard !metadata.isEmpty || !keyList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-json-preview">
          <div>
            \(metadata)
          </div>
          \(keyList)
        </div>
        """
    }

    private static func renderHARPreview(_ preview: ToolArtifactHARPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-har-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let hosts = preview.hostPreviewLabels.map {
            #"<li data-testid="tool-card-har-preview-host-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let hostList = hosts.isEmpty
            ? ""
            : """
              <section class="artifact-office-contents" data-testid="tool-card-har-preview-hosts">
                <strong data-testid="tool-card-har-preview-host-title">Hosts</strong>
                <ul>\(hosts)</ul>
              </section>
            """
        guard !metadata.isEmpty || !hostList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-har-preview">
          <div>
            \(metadata)
          </div>
          \(hostList)
        </div>
        """
    }

    private static func renderIstanbulPreview(_ preview: ToolArtifactIstanbulPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-istanbul-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let files = preview.filePreviewLabels.map {
            #"<li data-testid="tool-card-istanbul-preview-file-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let fileList = files.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-istanbul-preview-files">
                <strong data-testid="tool-card-istanbul-preview-file-title">Source files</strong>
                <ul>\(files)</ul>
              </section>
        """
        guard !metadata.isEmpty || !fileList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-istanbul-preview">
          <div>
            \(metadata)
          </div>
          \(fileList)
        </div>
        """
    }

    private static func renderCoveragePyPreview(_ preview: ToolArtifactCoveragePyPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-coverage-py-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let files = preview.filePreviewLabels.map {
            #"<li data-testid="tool-card-coverage-py-preview-file-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let fileList = files.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-coverage-py-preview-files">
                <strong data-testid="tool-card-coverage-py-preview-file-title">Source files</strong>
                <ul>\(files)</ul>
              </section>
        """
        guard !metadata.isEmpty || !fileList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-coverage-py-preview">
          <div>
            \(metadata)
          </div>
          \(fileList)
        </div>
        """
    }

    private static func renderPytestJSONPreview(_ preview: ToolArtifactPytestJSONPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-pytest-json-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let failures = preview.failurePreviewLabels.map {
            #"<li data-testid="tool-card-pytest-json-preview-failure-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let failureList = failures.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-pytest-json-preview-failures">
                <strong data-testid="tool-card-pytest-json-preview-failure-title">Failures</strong>
                <ul>\(failures)</ul>
              </section>
        """
        guard !metadata.isEmpty || !failureList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-pytest-json-preview">
          <div>
            \(metadata)
          </div>
          \(failureList)
        </div>
        """
    }

    private static func renderJestJSONPreview(_ preview: ToolArtifactJestJSONPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-jest-json-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let failures = preview.failurePreviewLabels.map {
            #"<li data-testid="tool-card-jest-json-preview-failure-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let failureList = failures.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-jest-json-preview-failures">
                <strong data-testid="tool-card-jest-json-preview-failure-title">Failures</strong>
                <ul>\(failures)</ul>
              </section>
        """
        guard !metadata.isEmpty || !failureList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-jest-json-preview">
          <div>
            \(metadata)
          </div>
          \(failureList)
        </div>
        """
    }

    private static func renderTAPPreview(_ preview: ToolArtifactTAPPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-tap-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let failures = preview.failurePreviewLabels.map {
            #"<li data-testid="tool-card-tap-preview-failure-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let failureList = failures.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-tap-preview-failures">
                <strong data-testid="tool-card-tap-preview-failure-title">Failures</strong>
                <ul>\(failures)</ul>
              </section>
        """
        guard !metadata.isEmpty || !failureList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-tap-preview">
          <div>
            \(metadata)
          </div>
          \(failureList)
        </div>
        """
    }

    private static func renderLCOVPreview(_ preview: ToolArtifactLCOVPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-lcov-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let sourceFiles = preview.sourcePreviewLabels.map {
            #"<li data-testid="tool-card-lcov-preview-source-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let sourceList = sourceFiles.isEmpty
            ? ""
            : """
              <section class="artifact-office-contents" data-testid="tool-card-lcov-preview-sources">
                <strong data-testid="tool-card-lcov-preview-source-title">Source files</strong>
                <ul>\(sourceFiles)</ul>
              </section>
            """
        guard !metadata.isEmpty || !sourceList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-lcov-preview">
          <div>
            \(metadata)
          </div>
          \(sourceList)
        </div>
        """
    }

    private static func renderGoCoveragePreview(_ preview: ToolArtifactGoCoveragePreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-go-coverage-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let sourceFiles = preview.sourcePreviewLabels.map {
            #"<li data-testid="tool-card-go-coverage-preview-source-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let sourceList = sourceFiles.isEmpty
            ? ""
            : """
              <section class="artifact-office-contents" data-testid="tool-card-go-coverage-preview-sources">
                <strong data-testid="tool-card-go-coverage-preview-source-title">Source files</strong>
                <ul>\(sourceFiles)</ul>
              </section>
            """
        guard !metadata.isEmpty || !sourceList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-go-coverage-preview">
          <div>
            \(metadata)
          </div>
          \(sourceList)
        </div>
        """
    }

    private static func renderSARIFPreview(_ preview: ToolArtifactSARIFPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-sarif-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let tools = preview.toolPreviewLabels.map {
            #"<li data-testid="tool-card-sarif-preview-tool-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let rules = preview.rulePreviewLabels.map {
            #"<li data-testid="tool-card-sarif-preview-rule-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let toolList = tools.isEmpty
            ? ""
            : """
              <section class="artifact-office-contents" data-testid="tool-card-sarif-preview-tools">
                <strong data-testid="tool-card-sarif-preview-tool-title">Tools</strong>
                <ul>\(tools)</ul>
              </section>
            """
        let ruleList = rules.isEmpty
            ? ""
            : """
              <section class="artifact-office-contents" data-testid="tool-card-sarif-preview-rules">
                <strong data-testid="tool-card-sarif-preview-rule-title">Rules</strong>
                <ul>\(rules)</ul>
              </section>
            """
        guard !metadata.isEmpty || !toolList.isEmpty || !ruleList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-sarif-preview">
          <div>
            \(metadata)
          </div>
          \(toolList)
          \(ruleList)
        </div>
        """
    }

    private static func renderJSONLinesPreview(_ preview: ToolArtifactJSONLinesPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-json-lines-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let keys = preview.keyPreviewLabels.map {
            #"<li data-testid="tool-card-json-lines-preview-key-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let keyList = keys.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-json-lines-preview-keys">
                <strong data-testid="tool-card-json-lines-preview-key-title">Observed keys</strong>
                <ul>\(keys)</ul>
              </section>
        """
        guard !metadata.isEmpty || !keyList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-json-lines-preview">
          <div>
            \(metadata)
          </div>
          \(keyList)
        </div>
        """
    }

    private static func renderTOMLPreview(_ preview: ToolArtifactTOMLPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-toml-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let keys = preview.keyPreviewLabels.map {
            #"<li data-testid="tool-card-toml-preview-key-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let keyList = keys.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-toml-preview-keys">
                <strong data-testid="tool-card-toml-preview-key-title">Top-level keys</strong>
                <ul>\(keys)</ul>
              </section>
        """
        guard !metadata.isEmpty || !keyList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-toml-preview">
          <div>
            \(metadata)
          </div>
          \(keyList)
        </div>
        """
    }

    private static func renderINIPreview(_ preview: ToolArtifactINIPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-ini-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let sections = preview.sectionPreviewLabels.map {
            #"<li data-testid="tool-card-ini-preview-section-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let sectionList = sections.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-ini-preview-sections">
                <strong data-testid="tool-card-ini-preview-section-title">Sections</strong>
                <ul>\(sections)</ul>
              </section>
        """
        guard !metadata.isEmpty || !sectionList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-ini-preview">
          <div>
            \(metadata)
          </div>
          \(sectionList)
        </div>
        """
    }

    private static func renderDotenvPreview(_ preview: ToolArtifactDotenvPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-dotenv-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let keys = preview.keyPreviewLabels.map {
            #"<li data-testid="tool-card-dotenv-preview-key-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let keyList = keys.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-dotenv-preview-keys">
                <strong data-testid="tool-card-dotenv-preview-key-title">Variable names</strong>
                <ul>\(keys)</ul>
              </section>
        """
        guard !metadata.isEmpty || !keyList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-dotenv-preview">
          <div>
            \(metadata)
          </div>
          \(keyList)
        </div>
        """
    }

    private static func renderYAMLPreview(_ preview: ToolArtifactYAMLPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-yaml-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let keys = preview.keyPreviewLabels.map {
            #"<li data-testid="tool-card-yaml-preview-key-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let keyList = keys.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-yaml-preview-keys">
                <strong data-testid="tool-card-yaml-preview-key-title">Top-level keys</strong>
                <ul>\(keys)</ul>
              </section>
        """
        guard !metadata.isEmpty || !keyList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-yaml-preview">
          <div>
            \(metadata)
          </div>
          \(keyList)
        </div>
        """
    }

    private static func renderXMLPreview(_ preview: ToolArtifactXMLPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-xml-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let children = preview.childPreviewLabels.map {
            #"<li data-testid="tool-card-xml-preview-child-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let childList = children.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-xml-preview-children">
                <strong data-testid="tool-card-xml-preview-child-title">Root children</strong>
                <ul>\(children)</ul>
              </section>
        """
        guard !metadata.isEmpty || !childList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-xml-preview">
          <div>
            \(metadata)
          </div>
          \(childList)
        </div>
        """
    }

    private static func renderJUnitPreview(_ preview: ToolArtifactJUnitPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-junit-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let suites = preview.suitePreviewLabels.map {
            #"<li data-testid="tool-card-junit-preview-suite-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let failures = preview.failurePreviewLabels.map {
            #"<li data-testid="tool-card-junit-preview-failure-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let suiteList = suites.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-junit-preview-suites">
                <strong data-testid="tool-card-junit-preview-suite-title">Suites</strong>
                <ul>\(suites)</ul>
              </section>
        """
        let failureList = failures.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-junit-preview-failures">
                <strong data-testid="tool-card-junit-preview-failure-title">Failing tests</strong>
                <ul>\(failures)</ul>
              </section>
        """
        guard !metadata.isEmpty || !suiteList.isEmpty || !failureList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-junit-preview">
          <div>
            \(metadata)
          </div>
          \(suiteList)
          \(failureList)
        </div>
        """
    }

    private static func renderTRXPreview(_ preview: ToolArtifactTRXPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-trx-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let failures = preview.failurePreviewLabels.map {
            #"<li data-testid="tool-card-trx-preview-failure-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let failureList = failures.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-trx-preview-failures">
                <strong data-testid="tool-card-trx-preview-failure-title">Failing tests</strong>
                <ul>\(failures)</ul>
              </section>
        """
        guard !metadata.isEmpty || !failureList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-trx-preview">
          <div>
            \(metadata)
          </div>
          \(failureList)
        </div>
        """
    }

    private static func renderXUnitPreview(_ preview: ToolArtifactXUnitPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-xunit-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let assemblies = preview.assemblyPreviewLabels.map {
            #"<li data-testid="tool-card-xunit-preview-assembly-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let failures = preview.failurePreviewLabels.map {
            #"<li data-testid="tool-card-xunit-preview-failure-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let assemblyList = assemblies.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-xunit-preview-assemblies">
                <strong data-testid="tool-card-xunit-preview-assembly-title">Assemblies</strong>
                <ul>\(assemblies)</ul>
              </section>
        """
        let failureList = failures.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-xunit-preview-failures">
                <strong data-testid="tool-card-xunit-preview-failure-title">Failing tests</strong>
                <ul>\(failures)</ul>
              </section>
        """
        guard !metadata.isEmpty || !assemblyList.isEmpty || !failureList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-xunit-preview">
          <div>
            \(metadata)
          </div>
          \(assemblyList)
          \(failureList)
        </div>
        """
    }

    private static func renderNUnitPreview(_ preview: ToolArtifactNUnitPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-nunit-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let failures = preview.failurePreviewLabels.map {
            #"<li data-testid="tool-card-nunit-preview-failure-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let failureList = failures.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-nunit-preview-failures">
                <strong data-testid="tool-card-nunit-preview-failure-title">Failing tests</strong>
                <ul>\(failures)</ul>
              </section>
        """
        guard !metadata.isEmpty || !failureList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-nunit-preview">
          <div>
            \(metadata)
          </div>
          \(failureList)
        </div>
        """
    }

    private static func renderCoberturaPreview(_ preview: ToolArtifactCoberturaPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-cobertura-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let packages = preview.packagePreviewLabels.map {
            #"<li data-testid="tool-card-cobertura-preview-package-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let classes = preview.classPreviewLabels.map {
            #"<li data-testid="tool-card-cobertura-preview-class-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let packageList = packages.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-cobertura-preview-packages">
                <strong data-testid="tool-card-cobertura-preview-package-title">Packages</strong>
                <ul>\(packages)</ul>
              </section>
        """
        let classList = classes.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-cobertura-preview-classes">
                <strong data-testid="tool-card-cobertura-preview-class-title">Classes</strong>
                <ul>\(classes)</ul>
              </section>
        """
        guard !metadata.isEmpty || !packageList.isEmpty || !classList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-cobertura-preview">
          <div>
            \(metadata)
          </div>
          \(packageList)
          \(classList)
        </div>
        """
    }

    private static func renderCloverPreview(_ preview: ToolArtifactCloverPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-clover-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let projects = preview.projectPreviewLabels.map {
            #"<li data-testid="tool-card-clover-preview-project-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let files = preview.filePreviewLabels.map {
            #"<li data-testid="tool-card-clover-preview-file-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let projectList = projects.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-clover-preview-projects">
                <strong data-testid="tool-card-clover-preview-project-title">Projects</strong>
                <ul>\(projects)</ul>
              </section>
        """
        let fileList = files.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-clover-preview-files">
                <strong data-testid="tool-card-clover-preview-file-title">Files</strong>
                <ul>\(files)</ul>
              </section>
        """
        guard !metadata.isEmpty || !projectList.isEmpty || !fileList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-clover-preview">
          <div>
            \(metadata)
          </div>
          \(projectList)
          \(fileList)
        </div>
        """
    }

    private static func renderJaCoCoPreview(_ preview: ToolArtifactJaCoCoPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-jacoco-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let packages = preview.packagePreviewLabels.map {
            #"<li data-testid="tool-card-jacoco-preview-package-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let sourceFiles = preview.sourceFilePreviewLabels.map {
            #"<li data-testid="tool-card-jacoco-preview-source-file-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let packageList = packages.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-jacoco-preview-packages">
                <strong data-testid="tool-card-jacoco-preview-package-title">Packages</strong>
                <ul>\(packages)</ul>
              </section>
        """
        let sourceFileList = sourceFiles.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-jacoco-preview-source-files">
                <strong data-testid="tool-card-jacoco-preview-source-file-title">Source files</strong>
                <ul>\(sourceFiles)</ul>
              </section>
        """
        guard !metadata.isEmpty || !packageList.isEmpty || !sourceFileList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-jacoco-preview">
          <div>
            \(metadata)
          </div>
          \(packageList)
          \(sourceFileList)
        </div>
        """
    }

    private static func renderPropertyListPreview(_ preview: ToolArtifactPropertyListPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-plist-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        let keys = preview.keyPreviewLabels.map {
            #"<li data-testid="tool-card-plist-preview-key-item">\#(escape($0))</li>"#
        }.joined(separator: "")
        let keyList = keys.isEmpty ? "" : """
              <section class="artifact-office-contents" data-testid="tool-card-plist-preview-keys">
                <strong data-testid="tool-card-plist-preview-key-title">Top-level keys</strong>
                <ul>\(keys)</ul>
              </section>
        """
        guard !metadata.isEmpty || !keyList.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-plist-preview">
          <div>
            \(metadata)
          </div>
          \(keyList)
        </div>
        """
    }

    private static func renderSQLitePreview(_ preview: ToolArtifactSQLitePreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-sqlite-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-sqlite-preview">
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderWebAssemblyPreview(_ preview: ToolArtifactWebAssemblyPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-wasm-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-wasm-preview">
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderFontPreview(_ preview: ToolArtifactFontPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-font-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-font-preview">
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderExecutablePreview(_ preview: ToolArtifactExecutablePreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-executable-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-executable-preview">
          <div>
            \(metadata)
          </div>
        </div>
        """
    }

    private static func renderNotebookPreview(_ preview: ToolArtifactNotebookPreview?) -> String {
        guard let preview, preview.hasDisplayContent else { return "" }
        let metadata = preview.metadataLines.map {
            #"<small data-testid="tool-card-notebook-preview-meta">\#(escape($0))</small>"#
        }.joined(separator: "")
        guard !metadata.isEmpty else { return "" }
        return """
        <div class="artifact-office-preview" data-testid="tool-card-notebook-preview">
          <div>
            \(metadata)
          </div>
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
        let replay = renderAppshotReplay(preview)
        guard !image.isEmpty || !title.isEmpty || !summary.isEmpty || !metadata.isEmpty || !replay.isEmpty else {
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
          \(replay)
        </div>
        """
    }

    private static func renderAppshotReplay(_ preview: ToolArtifactAppshotPreview) -> String {
        let groups = [
            ("Actions", preview.actionLabels),
            ("Frames", preview.frameLabels),
            ("Events", preview.eventLabels)
        ].filter { !$0.1.isEmpty }
        guard !groups.isEmpty else { return "" }
        return groups.map { title, labels in
            let items = labels.enumerated().map { index, label in
                #"<li data-testid="tool-card-appshot-replay-item"><span>\#(index + 1)</span>\#(escape(label))</li>"#
            }.joined(separator: "")
            return """
            <section class="artifact-appshot-replay-group" data-testid="tool-card-appshot-replay-group">
              <strong data-testid="tool-card-appshot-replay-title">\(escape(title))</strong>
              <ol>\(items)</ol>
            </section>
            """
        }.joined(separator: "")
    }

    private static func documentIcon(for kind: ToolArtifactDocumentKind) -> String {
        switch kind {
        case .appshot:
            return "APP"
        case .pdf:
            return "PDF"
        case .markdown:
            return "MD"
        case .data:
            return "JSON"
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
