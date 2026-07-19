import Foundation
import QuillCodeApp

extension QuillCodeDesktopController {
    /// Resumes a failed run from a tapped Retry notification action.
    ///
    /// Order matters here (review round on #1369):
    /// 1. GATE first — a stale tap (the thread already resumed, or was destroyed) must be a pure
    ///    no-op: it must not even navigate, because `selectThread` has real side effects (it destroys
    ///    a live confidential session, cancels a streaming side conversation). The default tap still
    ///    opens the app for "come look".
    /// 2. Take the `.send` slot BEFORE selecting the thread — `selectThread` internally starts the
    ///    follow-up recovery drain in the same slot, which would otherwise swallow the retry and run
    ///    the queued follow-ups as if the failed turn had succeeded. With the retry holding the slot,
    ///    the recovery drain's own `startIfIdle` refuses, and the retry's `drainFollowUpQueue` runs
    ///    the queue AFTER the continuation turn — the correct order.
    /// If a send is literally starting concurrently (slot busy but the run not yet registered), the
    /// retry is dropped: the thread is resuming anyway, so a continuation would be redundant.
    func retryFailedRunFromNotification(threadID: UUID) {
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
        if model.selectedThread?.id != threadID {
            selectThread(threadID)
        }
        refresh()
    }
}
