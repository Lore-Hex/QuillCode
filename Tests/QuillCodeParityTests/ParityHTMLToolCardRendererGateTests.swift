import XCTest

final class ParityHTMLToolCardRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesToolCardRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let toolCardText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let primitivesText = try Self.appSourceText(named: "WorkspaceHTMLPrimitives.swift")

        assertToolCardRendererContracts(toolCardText)
        assertSharedPrimitiveContracts(primitivesText)
        assertToolCardDelegation(htmlText, transcriptText, toolCardText)
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
