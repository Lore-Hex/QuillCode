import Foundation
import QuillCodeCore

/// Retry-a-failed-run: the model-level gate and turn for resuming a thread whose LAST run died on an
/// error, triggered from the failed-run OS notification's Retry button (and any future in-app retry
/// affordance — both must route through here). Guards live at the MODEL level, not the notification
/// layer, per the typed-command-bypass lesson: any surface that can reach this API gets the same
/// validation.
extension QuillCodeWorkspaceModel {
    /// The continuation prompt a retry sends. Deliberately a *continue* instruction, not a re-send of
    /// the original message: the thread already carries the task and the durable failure notice, and
    /// tools may have partially executed before the failure — the model must verify partial work
    /// rather than blindly redo it.
    public static let failedRunRetryPrompt =
        "The previous run stopped on an error. Continue the task from where it left off — check the "
        + "state of any partial work from the last attempt before redoing it."

    /// Whether a notification-tapped retry is valid for this thread right now: the thread exists, no
    /// run is active for it, and its history ends in a failed run (a persisted run-failure notice with
    /// no completed work after it — trailing notices like the run-integrity verdict are tolerated).
    public func canRetryFailedRun(threadID: UUID) -> Bool {
        guard let thread = root.threads.first(where: { $0.id == threadID }) else { return false }
        guard !isAgentRunActive(for: threadID) else { return false }
        return Self.lastRunFailed(in: thread)
    }

    /// Runs the retry turn through the SAME shared engine as composer/follow-up turns (`runAgentTurn`),
    /// then drains any queued follow-ups — so a retried wave continues exactly like a resumed one.
    /// No-ops (without touching the thread) when the gate no longer holds, e.g. the user already
    /// resumed the thread by hand between the notification and the tap.
    public func retryFailedRun(
        threadID: UUID,
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)? = nil,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async {
        guard canRetryFailedRun(threadID: threadID) else { return }
        guard let first = await runAgentTurn(
            prompt: Self.failedRunRetryPrompt,
            threadID: threadID,
            clearingDraftFor: nil,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        ) else { return }
        await drainFollowUpQueue(
            after: first,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        )
    }

    /// True when the thread's most recent substantive event is a persisted run-failure notice.
    /// Scans from the end: trailing `.notice` events that are not the failure itself (run-integrity
    /// verdict, token usage) are skipped; any message/tool event before the failure notice means the
    /// thread has moved on and the failure is stale.
    static func lastRunFailed(in thread: ChatThread) -> Bool {
        for event in thread.events.reversed() {
            if event.kind == .notice {
                if event.summary.hasPrefix(WorkspaceRunFailureNoticePlanner.noticePrefix) {
                    return true
                }
                continue
            }
            return false
        }
        return false
    }
}
