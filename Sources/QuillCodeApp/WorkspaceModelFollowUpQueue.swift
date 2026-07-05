import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    /// The selected thread's follow-up queue, surfaced for the composer chips. Empty when no
    /// thread is selected.
    public var followUpQueue: [FollowUpItem] {
        selectedThread?.followUpQueue ?? []
    }

    /// Parks a composer submission entered during an active run as a follow-up chip on the
    /// selected thread instead of locking the composer. Empty/whitespace text is ignored (no
    /// chip). Persists with the thread so the queue survives a reload. Returns true when a
    /// chip was actually enqueued.
    ///
    /// This is the "never-locking" half of the submit path: the desktop coordinator calls it
    /// (rather than the old silent-reject guard) whenever a submit arrives while `isSending`.
    @discardableResult
    public func enqueueFollowUp(_ text: String) -> Bool {
        if selectedThread == nil {
            _ = newChat()
        }
        guard selectedThread != nil else { return false }
        var appended = false
        mutateSelectedThread { thread in
            let result = FollowUpQueue.enqueue(text, into: thread.followUpQueue)
            thread.followUpQueue = result.queue
            appended = result.appended != nil
        }
        if appended {
            composer.draft = ""
            clearComposerDraft(for: root.selectedThreadID)
        }
        return appended
    }

    /// Removes a queued follow-up by id (a chip's delete affordance). A no-op for an unknown
    /// id, so deleting an already-drained chip is harmless. Persists with the thread. Deleting
    /// a chip before its turn drains guarantees it is never sent.
    public func deleteFollowUp(_ id: UUID) {
        mutateSelectedThread { thread in
            thread.followUpQueue = FollowUpQueue.delete(id, from: thread.followUpQueue)
        }
    }

    /// Pops the run thread's next queued follow-up at a turn boundary, if any, returning its
    /// text to send as the next turn. Removes exactly the head item (drain-exactly-once) and
    /// persists the shrunken queue before the send starts, so a crash mid-drain never replays
    /// the same item. Returns nil when the run thread has no queued items — the drain loop in
    /// `submitComposer` then stops.
    ///
    /// Drains from the RUN's thread (`runThreadID`), not whatever thread is selected now, so a
    /// mid-run thread switch never drains the wrong queue or drops the run thread's items.
    func drainNextFollowUp(runThreadID: UUID) -> String? {
        var next: FollowUpItem?
        mutateThread(runThreadID) { thread in
            let result = FollowUpQueue.dequeue(thread.followUpQueue)
            next = result.next
            thread.followUpQueue = result.remaining
        }
        return next?.text
    }
}
