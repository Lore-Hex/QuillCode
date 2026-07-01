import XCTest

final class ParityHTMLTranscriptRendererGateTests: QuillCodeParityTestCase {
    func testWorkspaceHTMLRendererDelegatesTranscriptRendering() throws {
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLRenderer.swift")
        let transcriptText = try Self.appSourceText(named: "WorkspaceHTMLTranscriptRenderer.swift")

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
        ].forEach { Self.assertSource(transcriptText, contains: $0) }
        [
            "WorkspaceHTMLTranscriptRenderer.render",
            "WorkspaceHTMLTranscriptRenderer.renderComposer"
        ].forEach { Self.assertSource(htmlText, contains: $0) }
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
