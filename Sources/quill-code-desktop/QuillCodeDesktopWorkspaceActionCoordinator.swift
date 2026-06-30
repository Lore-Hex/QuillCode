import Foundation
import QuillCodeApp
import QuillCodeCore

@MainActor
struct QuillCodeDesktopWorkspaceActionCoordinator {
    func runToolCardAction(
        _ action: ToolCardActionSurface,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL,
        tasks: QuillCodeDesktopTaskCoordinator,
        refresh: @escaping @MainActor () -> Void
    ) {
        let workspaceRoot = activeWorkspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        guard action.kind == .approve else {
            // Skip / edit are immediate, local, and unaffected by any in-flight send.
            _ = model.runToolCardAction(action, workspaceRoot: workspaceRoot)
            return
        }
        // Approving runs the held tool AND resumes the plan. Route the WHOLE thing through the
        // same `.send` slot a composer send uses (and gate on it up front, mirroring the composer),
        // so the held tool + resume are atomic, Stop cancels them, and they never interleave with
        // another send. `approveToolCardAndResume` is exactly the method the tests drive.
        guard !tasks.isRunning(.send) else { return }
        tasks.startIfIdle(.send) { [weak model] in
            _ = await model?.approveToolCardAndResume(action, workspaceRoot: workspaceRoot)
        } onFinish: {
            refresh()
        }
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

    func runTurnRevert(
        turnMessageID: UUID,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        model.runTurnRevert(
            turnMessageID: turnMessageID,
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

    func updatePullRequestReviewDraft(
        _ draft: WorkspacePullRequestReviewDraftSurface,
        model: QuillCodeWorkspaceModel
    ) {
        model.updatePullRequestReviewDraft(draft)
    }

    func cancelPullRequestReviewDraft(model: QuillCodeWorkspaceModel) {
        model.cancelPullRequestReviewDraft()
    }

    func submitPullRequestReviewDraft(
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        _ = model.submitPullRequestReviewDraft(
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
