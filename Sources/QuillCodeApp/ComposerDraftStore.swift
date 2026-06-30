import Foundation

/// Pure logic for preserving a separate unsent composer draft per thread, so
/// switching threads stashes the outgoing draft and restores the incoming one
/// instead of bleeding a single shared draft across threads. The workspace model
/// owns the `[UUID: String]` map; this type computes the next map and the draft to
/// show on each switch, keeping the branching unit-testable in isolation.
public enum ComposerDraftStore {
    /// The outcome of switching threads: the updated draft map and the draft to
    /// restore into the composer for the newly selected thread.
    public struct Switch: Equatable {
        public var drafts: [UUID: String]
        public var restoredDraft: String

        public init(drafts: [UUID: String], restoredDraft: String) {
            self.drafts = drafts
            self.restoredDraft = restoredDraft
        }
    }

    /// Stashes the outgoing thread's live draft and restores the incoming thread's
    /// saved draft. Empty/whitespace drafts are not stored. Selecting the same
    /// thread is a no-op that keeps the live draft as-is.
    public static func select(
        outgoing: UUID?,
        incoming: UUID,
        liveDraft: String,
        drafts: [UUID: String]
    ) -> Switch {
        if outgoing == incoming {
            return Switch(drafts: drafts, restoredDraft: liveDraft)
        }

        var next = drafts
        if let outgoing {
            if liveDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                next[outgoing] = nil
            } else {
                next[outgoing] = liveDraft
            }
        }

        let restored = next[incoming] ?? ""
        next[incoming] = nil
        return Switch(drafts: next, restoredDraft: restored)
    }

    /// Drops a thread's saved draft, for use when its draft is sent or the thread
    /// is removed.
    public static func cleared(_ id: UUID?, drafts: [UUID: String]) -> [UUID: String] {
        guard let id else { return drafts }
        var next = drafts
        next[id] = nil
        return next
    }
}
