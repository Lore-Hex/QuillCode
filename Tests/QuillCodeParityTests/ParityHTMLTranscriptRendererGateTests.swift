import XCTest

final class ParityHTMLTranscriptRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesReviewRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")
        let reviewText = try Self.appSourceText(named: "WorkspaceHTMLReviewRenderer.swift")

        assertReviewRendererContracts(reviewText)
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTranscriptRenderer.render")
        Self.assertSource(transcriptText, contains: "WorkspaceHTMLReviewRenderer.render")
        assertWorkspaceRendererAvoidsReviewOwnership(htmlText)
    }

    func testWorkspaceHTMLRendererDelegatesTranscriptRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")

        assertTranscriptRendererContracts(transcriptText)
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTranscriptRenderer.render")
        Self.assertSource(htmlText, contains: "WorkspaceHTMLTranscriptRenderer.renderComposer")
        assertWorkspaceRendererAvoidsTranscriptOwnership(htmlText)
    }

    private func assertReviewRendererContracts(_ source: String) {
        [
            "enum WorkspaceHTMLReviewRenderer",
            "static func render(_ review: WorkspaceReviewSurface",
            "private static func renderFile",
            "private static func renderHunk",
            "private static func renderLine",
            "private static func renderAction",
            "WorkspaceHTMLPrimitives.escape"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertWorkspaceRendererAvoidsReviewOwnership(_ htmlText: String) {
        [
            "private static func renderReview",
            "private static func renderReviewHunk",
            "private static func renderReviewLine",
            "private static func renderReviewAction",
            "review-hunk-header",
            "review-line-marker"
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }

    private func assertTranscriptRendererContracts(_ source: String) {
        [
            "enum WorkspaceHTMLTranscriptRenderer",
            "static func render(",
            "static func renderComposer",
            "private static func renderRuntimeIssue",
            "private static func renderTimelineItem",
            "private static func renderContextBanner",
            "WorkspaceHTMLToolCardRenderer.render",
            "WorkspaceHTMLReviewRenderer.render",
            "WorkspaceHTMLPrimitives.escape"
        ].forEach { Self.assertSource(source, contains: $0) }
    }

    private func assertWorkspaceRendererAvoidsTranscriptOwnership(_ htmlText: String) {
        [
            "private static func renderTranscript",
            "private static func renderRuntimeIssue",
            "private static func renderTimelineItem",
            "private static func renderMessageFeedbackActions",
            "private static func renderContextBanner",
            "private static func renderComposer",
            #"data-testid="message-feedback-up""#,
            #"data-testid="runtime-issue""#,
            #"data-testid="context-banner""#
        ].forEach { Self.assertSource(htmlText, excludes: $0) }
    }
}
