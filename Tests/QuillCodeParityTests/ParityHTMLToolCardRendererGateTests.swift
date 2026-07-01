import XCTest

final class ParityHTMLToolCardRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesToolCardRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let toolCardText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")

        [
            "enum WorkspaceHTMLToolCardRenderer",
            "static func render(_ card: ToolCardState",
            "private static func renderArtifacts",
            "private static func renderTextPreviews",
            "private static func renderDocumentPreviews",
            "private static func renderImagePreviews",
            "WorkspaceHTMLPrimitives.executionContextChip"
        ].forEach { Self.assertSource(toolCardText, contains: $0) }
        [
            "enum WorkspaceHTMLPrimitives",
            "static func escape",
            "static func executionContextChip"
        ].forEach { Self.assertSource(primitivesText, contains: $0) }
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTranscriptRenderer.render")
        Self.assertSource(transcriptText, contains: "WorkspaceHTMLToolCardRenderer.render")
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
