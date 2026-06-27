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
