import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
struct QuillCodeDesktopWorkspaceActionCoordinator {
    func runToolCardAction(
        _ action: ToolCardActionSurface,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        _ = model.runToolCardAction(
            action,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func runReviewAction(
        _ action: WorkspaceReviewActionSurface,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runReviewAction(
            action,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func runPullRequestReviewThreadAction(
        _ action: WorkspacePullRequestReviewThreadActionSurface,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runPullRequestReviewThreadAction(
            action,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func runPullRequestReviewThreadReply(
        _ request: WorkspacePullRequestReviewThreadReplyRequest,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runPullRequestReviewThreadReply(
            request,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    func useComposerDraft(_ draft: String, model: QuillCodeWorkspaceModel) {
        model.setDraft(draft)
    }

    func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int?,
        lineKind: WorkspaceReviewLineKind?,
        text: String,
        model: QuillCodeWorkspaceModel
    ) {
        _ = model.addReviewComment(
            path: path,
            lineNumber: lineNumber,
            endLineNumber: endLineNumber,
            lineKind: lineKind,
            text: text
        )
    }

    @discardableResult
    func setMessageFeedback(
        messageID: UUID,
        value: MessageFeedbackValue,
        model: QuillCodeWorkspaceModel
    ) -> Bool {
        model.setMessageFeedback(messageID: messageID, value: value)
    }

    @discardableResult
    func runWorkspaceCommand(
        _ commandID: String,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) -> Bool {
        model.runWorkspaceCommand(
            commandID,
            workspaceRoot: activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        )
    }

    private func activeWorkspaceRoot(for model: QuillCodeWorkspaceModel, fallback: URL) -> URL {
        model.activeWorkspaceRoot ?? fallback
    }
}
