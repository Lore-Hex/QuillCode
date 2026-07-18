import XCTest

final class ParityHTMLToolCardRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesToolCardRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let toolCardText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")
        let harnessText = try String(
            contentsOf: Self.packageRoot().appendingPathComponent("E2E/harness/index.html"),
            encoding: .utf8
        )

        assertToolCardRendererContracts(toolCardText)
        assertSharedPrimitiveContracts(primitivesText)
        assertToolCardDelegation(htmlText, transcriptText, toolCardText)
        assertArtifactPreviewContracts(toolCardText, harnessText)
        assertWorkspaceRendererAvoidsToolCardOwnership(htmlText)
    }

    private func assertToolCardRendererContracts(_ source: String) {
        [
            "enum WorkspaceHTMLToolCardRenderer",
            "static func render(_ card: ToolCardState",
            "private static func renderArtifacts",
            "private static func renderTextPreviews",
            "private static func renderDocumentPreviews",
            "private static func renderImagePreviews"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertSharedPrimitiveContracts(_ source: String) {
        [
            "enum WorkspaceHTMLPrimitives",
            "static func escape",
            "static func executionContextChip"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertToolCardDelegation(
        _ htmlText: String,
        _ transcriptText: String,
        _ toolCardText: String
    ) {
        Self.assertSource(
            toolCardText,
            contains: "WorkspaceHTMLPrimitives.executionContextChip"
        )
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTranscriptRenderer.render")
        Self.assertSource(transcriptText, contains: "WorkspaceHTMLToolCardRenderer.render")
    }

    private func assertArtifactPreviewContracts(_ toolCardText: String, _ harnessText: String) {
        Self.assertSource(toolCardText, containsAll: [
            "renderPDFPreview(artifact.pdfPreview, href: artifact.href)",
            "artifact.sourceTextPreview?.metadataLines",
            #"data-testid="tool-card-text-preview-meta""#,
            "private static func renderLocalPDFPagePreview",
            "url.isFileURL",
            #"data-testid="tool-card-pdf-page-preview""#,
            #"type="application/pdf""#,
            "#page=1",
            #"data-testid="tool-card-pdf-page-preview-fallback""#,
            "private static func renderAppshotReplay",
            "preview.actionLabels",
            "preview.frameLabels",
            "preview.eventLabels",
            "tool-card-image-preview-sequence",
            #"data-testid="tool-card-appshot-replay-group""#,
            #"data-testid="tool-card-appshot-replay-item""#,
            "preview.contentPreviewLabels",
            #"data-testid="tool-card-office-preview-contents""#,
            #"data-testid="tool-card-office-preview-content-item""#,
            "renderRTFPreview(artifact.rtfPreview)",
            #"data-testid="tool-card-rtf-preview-meta""#,
            "renderHTMLPreview(artifact.htmlPreview)",
            #"data-testid="tool-card-html-preview-meta""#,
            "preview.entryPreviewLabels",
            #"data-testid="tool-card-archive-preview-entries""#,
            #"data-testid="tool-card-archive-preview-entry-item""#
        ])
        Self.assertSource(harnessText, containsAll: [
            "const localPDFPreviewObject",
            "artifact.sourceTextPreview?.metadataLines",
            #"data-testid="tool-card-text-preview-meta""#,
            "href.startsWith('file://')",
            "renderPDFPreview(artifact.pdfPreview, href)",
            #"data-testid="tool-card-pdf-page-preview""#,
            #"type="application/pdf""#,
            "#page=1",
            "const renderAppshotReplay",
            "preview.actionLabels || []",
            "tool-card-image-preview-sequence",
            #"data-testid="tool-card-appshot-replay-group""#,
            #"data-testid="tool-card-appshot-replay-item""#,
            "officeContentPreviewLabels",
            #"data-testid="tool-card-office-preview-contents""#,
            #"data-testid="tool-card-office-preview-content-item""#,
            "artifactRTFPreview(value, kind, documentPreview)",
            "const renderRTFPreview",
            #"data-testid="tool-card-rtf-preview-meta""#,
            "artifactHTMLPreview(value, kind, documentPreview)",
            "const renderHTMLPreview",
            #"data-testid="tool-card-html-preview-meta""#,
            "archiveEntryPreviewLabels",
            #"data-testid="tool-card-archive-preview-entries""#,
            #"data-testid="tool-card-archive-preview-entry-item""#
        ])
    }

    private func assertWorkspaceRendererAvoidsToolCardOwnership(_ htmlText: String) {
        [
            "private static func renderToolCard",
            "private static func renderToolArtifacts",
            "private static func renderToolTextPreviews",
            "private static func renderToolDocumentPreviews",
            "private static func renderToolImagePreviews",
            "private static func documentIcon"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
