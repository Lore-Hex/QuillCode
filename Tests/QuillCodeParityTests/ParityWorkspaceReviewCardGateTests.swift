import XCTest

final class ParityWorkspaceReviewCardGateTests: QuillCodeParityTestCase {
    func testActionableReviewCardsStayWiredThroughSurfaces() throws {
        let modelText = try Self.appSourceText(named: "WorkspaceModel.swift")
        let reviewText = try Self.appSourceText(named: "WorkspaceModelReview.swift")
        let surfaceText = try Self.appSourceText(named: "QuillCodeToolCardSurface.swift")
        let viewText = try Self.appSourceText(named: "QuillCodeToolCardView.swift")
        let controlsText = try Self.appSourceText(named: "QuillCodeToolCardControls.swift")
        let artifactViewsText = try Self.appSourceText(named: "QuillCodeToolArtifactViews.swift")
        let detailsText = try Self.appSourceText(named: "QuillCodeToolCardDetailsView.swift")
        let transcriptText = try Self.appSourceText(named: "QuillCodeTranscriptView.swift")
        let workspaceText = try Self.appSourceText(named: "WorkspaceSwiftUIView.swift")
        let plannerText = try Self.appSourceText(named: "WorkspaceApprovalActionPlanner.swift")
        let htmlText = try Self.appSourceText(named: "WorkspaceHTMLToolCardRenderer.swift")
        let desktopAppText = try Self.desktopSourceText(named: "QuillCodeDesktopApp.swift")
        let desktopControllerText = try Self.desktopSourceText(
            named: "QuillCodeDesktopController.swift"
        )
        let desktopCoordinatorText = try Self.desktopSourceText(
            named: "QuillCodeDesktopWorkspaceActionCoordinator.swift"
        )

        Self.assertSource(surfaceText, containsAll: [
            "public struct ToolCardActionSurface",
            "public enum ToolCardReviewState",
            "case edit",
            "public var actions: [ToolCardActionSurface]",
            "public var reviewState: ToolCardReviewState",
            "statusDisplayLabel",
            "statusAccessibilityLabel"
        ])
        Self.assertSource(transcriptText, contains: "onToolCardAction")
        Self.assertSource(viewText, containsAll: [
            "QuillCodeToolCardActionRow",
            "card.statusDisplayLabel"
        ])
        Self.assertSource(controlsText, containsAll: [
            "struct QuillCodeToolCardActionRow",
            "struct QuillCodeToolStatusBadge",
            "struct QuillCodeExecutionContextChip",
            "struct QuillCodeExecutionRail"
        ])
        Self.assertSource(artifactViewsText, containsAll: [
            "struct QuillCodeArtifactChip",
            "struct QuillCodeArtifactTextPreview",
            "struct QuillCodeArtifactDocumentPreview",
            "struct QuillCodeArtifactImagePreview"
        ])
        Self.assertSource(detailsText, contains: "struct QuillCodeCodeBlock")
        Self.assertSource(viewText, excludesAll: [
            "struct QuillCodeToolCardActionRow",
            "struct QuillCodeArtifactImagePreview",
            "struct QuillCodeCodeBlock"
        ])
        Self.assertSource(workspaceText, contains: "onToolCardAction")
        Self.assertSource(reviewText, containsAll: [
            "func runToolCardAction",
            "WorkspaceApprovalActionPlanner.plan"
        ])
        Self.assertSource(htmlText, containsAll: [
            "data-testid=\"tool-card-actions\"",
            "card.statusDisplayLabel",
            "card.reviewState.rawValue"
        ])
        Self.assertSource(plannerText, containsAll: [
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
        Self.assertSource(
            desktopControllerText,
            contains: "workspaceActionCoordinator.runToolCardAction"
        )
        Self.assertSource(desktopCoordinatorText, contains: "model.runToolCardAction")
    }
}
