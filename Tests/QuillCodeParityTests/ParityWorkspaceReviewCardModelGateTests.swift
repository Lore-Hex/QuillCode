import XCTest

final class ParityWorkspaceReviewCardModelGateTests: QuillCodeParityTestCase {
    func testActionableReviewCardsStayWiredThroughSurfaces() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewExtensionText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let toolCardSurfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let toolCardViewText = try Self.appSourceText(named: "QuillCodeToolCardView.swift")
        let toolCardControlsText = try Self.appSourceText(named: "QuillCodeToolCardControls.swift")
        let toolArtifactViewsText = try [
            "QuillCodeArtifactChip.swift",
            "QuillCodeArtifactDocumentPreview.swift",
            "QuillCodeArtifactImagePreview.swift",
            "QuillCodeArtifactTextPreview.swift"
        ]
        .map { try Self.appSourceText(named: $0) }
        .joined(separator: "\n")
        let toolCardDetailsText = try Self.appSourceText(named: "QuillCodeToolCardDetailsView.swift")
        let transcriptViewText = try Self.appSourceText(named: "QuillCodeTranscriptView.swift")
        let workspaceViewText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let approvalPlannerText = try Self.appSourceText(named: "WorkspaceApprovalActionPlanner.swift")
        let htmlRendererText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let desktopAppText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let desktopControllerText = try Self.desktopControllerSourceText()
        let desktopActionCoordinatorText = try Self.desktopSourceText(
            named: "QuillCodeDesktopWorkspaceActionCoordinator.swift"
        )

        Self.assertSource(toolCardSurfaceText, containsAll: [
            "public struct ToolCardActionSurface",
            "public enum ToolCardReviewState",
            "case edit",
            "public var actions: [ToolCardActionSurface]",
            "public var reviewState: ToolCardReviewState",
            "statusDisplayLabel",
            "statusAccessibilityLabel"
        ])
        Self.assertSource(transcriptViewText, contains: "onToolCardAction")
        Self.assertSource(toolCardViewText, containsAll: [
            "QuillCodeToolCardActionRow",
            "card.statusDisplayLabel"
        ])
        Self.assertSource(toolCardControlsText, containsAll: [
            "struct QuillCodeToolCardActionRow",
            "struct QuillCodeToolStatusBadge",
            "struct QuillCodeExecutionContextChip",
            "struct QuillCodeExecutionRail"
        ])
        Self.assertSource(toolArtifactViewsText, containsAll: [
            "struct QuillCodeArtifactChip",
            "struct QuillCodeArtifactTextPreview",
            "struct QuillCodeArtifactDocumentPreview",
            "struct QuillCodeArtifactImagePreview",
            "artifact.officePreview"
        ])
        Self.assertSource(toolCardDetailsText, contains: "struct QuillCodeCodeBlock")
        Self.assertSource(toolCardViewText, excludesAll: [
            "struct QuillCodeToolCardActionRow",
            "struct QuillCodeArtifactImagePreview",
            "struct QuillCodeCodeBlock"
        ])
        Self.assertSource(workspaceViewText, contains: "onToolCardAction")
        Self.assertSource(reviewExtensionText, containsAll: [
            "func runToolCardAction",
            "WorkspaceApprovalActionPlanner.plan"
        ])
        Self.assertSource(htmlRendererText, containsAll: [
            "data-testid=\"tool-card-actions\"",
            "card.statusDisplayLabel",
            "card.reviewState.rawValue"
        ])
        Self.assertSource(approvalPlannerText, containsAll: [
            "enum WorkspaceApprovalActionPlanner",
            "static func pendingRequest",
            "WorkspaceApprovalEditDraftBuilder",
            "composerDraft"
        ])
        Self.assertSource(modelText, excludesAll: [
            "func runToolCardAction",
            "private func pendingApprovalRequest",
            "private func appendApprovalDecision",
            "approvalVerdict"
        ])
        Self.assertSource(desktopAppText, contains: "controller.runToolCardAction")
        Self.assertSource(desktopControllerText, contains: "workspaceActionCoordinator.runToolCardAction")
        Self.assertSource(desktopActionCoordinatorText, contains: "model.runToolCardAction")
    }
}
