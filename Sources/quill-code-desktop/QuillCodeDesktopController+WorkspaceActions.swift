import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
extension QuillCodeDesktopController {
    func runToolCardAction(_ action: ToolCardActionSurface) {
        workspaceActionCoordinator.runToolCardAction(
            action,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot,
            tasks: tasks,
            refresh: { [weak self] in self?.refresh() }
        )
        refresh()
    }

    func runTurnRevert(_ turnMessageID: UUID) {
        workspaceActionCoordinator.runTurnRevert(
            turnMessageID: turnMessageID,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        )
        refresh()
    }

    func runReviewAction(_ action: WorkspaceReviewActionSurface) {
        workspaceActionCoordinator.runReviewAction(action, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func runPullRequestReviewThreadAction(_ action: WorkspacePullRequestReviewThreadActionSurface) {
        workspaceActionCoordinator.runPullRequestReviewThreadAction(
            action,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        )
        refresh()
    }

    func runPullRequestReviewThreadReply(_ request: WorkspacePullRequestReviewThreadReplyRequest) {
        workspaceActionCoordinator.runPullRequestReviewThreadReply(
            request,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        )
        refresh()
    }

    func updatePullRequestReviewDraft(_ draft: WorkspacePullRequestReviewDraftSurface) {
        workspaceActionCoordinator.updatePullRequestReviewDraft(draft, model: model)
        refresh()
    }

    func cancelPullRequestReviewDraft() {
        workspaceActionCoordinator.cancelPullRequestReviewDraft(model: model)
        refresh()
    }

    func submitPullRequestReviewDraft() {
        workspaceActionCoordinator.submitPullRequestReviewDraft(model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func usePullRequestReviewThreadReplyDraft(_ draft: String) {
        workspaceActionCoordinator.useComposerDraft(draft, model: model)
        refresh()
    }

    func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int?,
        lineKind: WorkspaceReviewLineKind?,
        text: String
    ) {
        workspaceActionCoordinator.addReviewComment(
            path: path,
            lineNumber: lineNumber,
            endLineNumber: endLineNumber,
            lineKind: lineKind,
            text: text,
            model: model
        )
        refresh()
    }

    func setMessageFeedback(messageID: UUID, value: MessageFeedbackValue) {
        guard workspaceActionCoordinator.setMessageFeedback(messageID: messageID, value: value, model: model) else {
            return
        }
        refresh()
    }
}
