import XCTest

final class ParityHTMLReviewRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesReviewRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let reviewText = try Self.appSourceText(named: "WorkspaceHTMLReviewRenderer.swift")

        [
            "enum WorkspaceHTMLReviewRenderer",
            "static func render(_ review: WorkspaceReviewSurface",
            "private static func renderFile",
            "private static func renderHunk",
            "private static func renderLine",
            "private static func renderAction",
            "WorkspaceHTMLPrimitives.escape"
        ].forEach { Self.assertSource(reviewText, contains: $0) }
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTranscriptRenderer.render")
        Self.assertSource(transcriptText, contains: "WorkspaceHTMLReviewRenderer.render")
        [
            "private static func renderReview",
            "private static func renderReviewHunk",
            "private static func renderReviewLine",
            "private static func renderReviewAction",
            "review-hunk-header",
            "review-line-marker"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
