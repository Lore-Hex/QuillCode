import Foundation
import QuillCodeCore

/// Morning-triage inbox actions (issue #877). The Attention section's keyboard triage — j/k/Enter/a/d —
/// routes through these five methods. All ranking/selection/triage *semantics* live in the shared pure
/// `AttentionModel` / `ThreadTriageRecord` in `QuillCodeCore`; these methods are the thin app-layer glue
/// that persists the decision and refreshes the surface. The HTML harness mirrors this exact behavior.
///
/// Triage-key semantics (documented, matching the harness):
/// - `j` — move the Attention cursor down one row (clamps at the last row; no wrap).
/// - `k` — move the cursor up one row (clamps at the first row).
/// - `Enter` — open the selected thread's return digest (and select the thread in the workspace).
/// - `a` — **acknowledge** the selected thread: it has been reviewed and is fine. Removed from Attention,
///   its triage state persisted as `.acknowledged`. The cursor advances to the next row.
/// - `d` — **dismiss** the selected thread: not worth reviewing. Removed from Attention, persisted as
///   `.dismissed`. The cursor advances to the next row.
///
/// `a`/`d` on an empty section, or when nothing is selected, are no-ops.
@MainActor
extension QuillCodeWorkspaceModel {
    /// The current ranked Attention model, rebuilt fresh from the persisted records on the threads. The
    /// cursor is anchored to the sidebar's selected thread when that thread is itself an attention row.
    var attentionModel: AttentionModel {
        AttentionModel.build(from: root.threads, selectedThreadID: attentionCursorThreadID)
    }

    /// Move the Attention triage cursor down (`j`). No-op on an empty section.
    public func attentionMoveDown() {
        var model = attentionModel
        model.moveDown()
        setAttentionCursor(model.selectedThreadID)
    }

    /// Move the Attention triage cursor up (`k`). No-op on an empty section.
    public func attentionMoveUp() {
        var model = attentionModel
        model.moveUp()
        setAttentionCursor(model.selectedThreadID)
    }

    /// Open the return digest for the selected Attention row (`Enter`): select the thread in the
    /// workspace and present its digest card. No-op when nothing is selected.
    public func attentionOpenSelected() {
        guard let threadID = attentionModel.selectedThreadID else { return }
        openAttentionDigest(for: threadID)
    }

    /// Open the digest for a specific thread (also used when the user clicks a row).
    public func openAttentionDigest(for threadID: UUID) {
        guard root.threads.contains(where: { $0.id == threadID }) else { return }
        selectThread(threadID)
        attentionDigestThreadID = threadID
    }

    /// Close the open digest card.
    public func closeAttentionDigest() {
        attentionDigestThreadID = nil
    }

    /// Acknowledge the selected Attention row (`a`): persist `.acknowledged`, remove it from Attention,
    /// and advance the cursor to the next row. No-op on an empty section.
    public func attentionAcknowledgeSelected() {
        triageSelected(as: .acknowledged)
    }

    /// Dismiss the selected Attention row (`d`): persist `.dismissed`, remove it from Attention, and
    /// advance the cursor. No-op on an empty section.
    public func attentionDismissSelected() {
        triageSelected(as: .dismissed)
    }

    // MARK: - Internals

    /// The thread the Attention cursor should anchor to. When a digest is open, that thread wins so the
    /// cursor stays put; otherwise the sidebar's selected thread anchors it (so click and keyboard agree).
    private var attentionCursorThreadID: UUID? {
        attentionDigestThreadID ?? root.selectedThreadID
    }

    /// Move the cursor by selecting the target thread in the workspace, so the sidebar highlight and the
    /// Attention cursor stay in sync. A nil target (empty section) is a no-op.
    private func setAttentionCursor(_ threadID: UUID?) {
        guard let threadID else { return }
        selectThread(threadID)
    }

    private func triageSelected(as state: ThreadTriageState) {
        var model = attentionModel
        guard let threadID = model.selectedThreadID else { return }
        // Persist the triage decision onto the thread (survives reload); rebuild the ranked list without
        // the now-triaged row and advance the cursor to whatever takes its place.
        _ = mutateThread(threadID) { thread in
            ThreadTriageRecord.set(state, on: &thread)
        }
        // If the digest for this thread was open, close it — it is no longer in the inbox.
        if attentionDigestThreadID == threadID {
            attentionDigestThreadID = nil
        }
        // Advance the cursor: the rebuilt model no longer contains the triaged thread, so its
        // initializer selects the row that slid into that position (or the first row).
        model = AttentionModel.build(from: root.threads, selectedThreadID: nil)
        setAttentionCursor(model.selectedThreadID)
    }
}
