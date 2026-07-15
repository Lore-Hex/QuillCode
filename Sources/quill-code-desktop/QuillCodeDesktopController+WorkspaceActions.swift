import Foundation
import QuillCodeApp
import QuillCodeCore
import QuillCodeReview

@MainActor
extension QuillCodeDesktopController {
    func dismissCodeReview() {
        model.dismissCodeReview()
        refresh()
    }

    func runCodeReview(_ request: WorkspaceCodeReviewRequest) {
        let sourceThreadID = model.selectedThread?.id
        if request.delivery == .current,
           tasks.isSendRunning(threadID: sourceThreadID) || model.isAgentRunActive(for: sourceThreadID) {
            return
        }

        let root = model.activeWorkspaceRoot ?? workspaceRoot
        let reviewOwnerID = sourceThreadID ?? model.selectedProject?.id ?? UUID()
        let slot = QuillCodeDesktopTaskCoordinator.Slot.codeReview(reviewOwnerID)
        let didStart = tasks.startIfIdle(slot) { [weak self] in
            guard let self else { return }
            await model.runCodeReview(
                request,
                workspaceRoot: root,
                onProgressUpdated: { [weak self] in self?.refresh() }
            )
        } onFinish: { [weak self] in
            guard let self else { return }
            refresh()
            if request.delivery == .current {
                recoverFollowUpDrain(for: sourceThreadID)
            }
        }
        if didStart {
            model.dismissCodeReview()
        }
        refresh()
    }

    func loadSubagentTranscript(
        parentThreadID: UUID,
        runID: UUID,
        workerID: String
    ) -> WorkspaceSubagentTranscriptSurface? {
        let transcript = model.loadSubagentTranscript(
            parentThreadID: parentThreadID,
            runID: runID,
            workerID: workerID
        )
        refresh()
        return transcript
    }

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

    func deleteFollowUp(_ id: UUID) {
        model.deleteFollowUp(id)
        refresh()
    }

    func runReviewAction(_ action: WorkspaceReviewActionSurface) {
        workspaceActionCoordinator.runReviewAction(action, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func runReviewScopeChange(_ selection: WorkspaceReviewSelection) {
        workspaceActionCoordinator.runReviewScopeChange(
            selection,
            model: model,
            fallbackWorkspaceRoot: workspaceRoot
        )
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

}
