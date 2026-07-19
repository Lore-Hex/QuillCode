import Foundation
import QuillCodeApp

extension QuillCodeDesktopController {
    /// Resumes a failed run from a tapped Retry notification action. Selects the failed thread first
    /// (the notification may target a thread the user is not viewing), then dispatches through the
    /// same per-chat `.send` slot as a composer submit — so a retry serializes with any concurrent
    /// send exactly like a typed message would, and a stale tap on a thread that already resumed is
    /// refused by the model-level gate (`canRetryFailedRun`) without touching the thread.
    func retryFailedRunFromNotification(threadID: UUID) {
        if model.selectedThread?.id != threadID {
            selectThread(threadID)
        }
        guard model.canRetryFailedRun(threadID: threadID) else {
            refresh()
            return
        }
        let runRoot = model.workspaceRoot(forThreadID: threadID) ?? workspaceRoot
        tasks.startIfIdle(.send(threadID)) { [weak self] in
            guard let self else { return }
            await model.retryFailedRun(
                threadID: threadID,
                workspaceRoot: runRoot,
                onStarted: { [weak self] in self?.refresh() },
                onProgressUpdated: { [weak self] in self?.refresh() }
            )
        } onFinish: { [weak self] in
            self?.refresh()
        }
        refresh()
    }
}
