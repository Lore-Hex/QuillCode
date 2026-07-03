import Foundation
import QuillCodeCore
import QuillCodeTools

/// Deterministic derivation of the transcript's navigation anchors: the most recent turn that
/// produced an **error** (a failed tool run) and the most recent turn that produced a **diff**
/// (a file write / patch). These power the "jump to last error" and "jump to last diff"
/// affordances that every post-run investigation reaches for.
///
/// Everything is derived purely from the shared `TranscriptSurface` timeline, so the native
/// SwiftUI transcript, the HTML render, and the Playwright harness all agree on which item the
/// jump targets. No force-unwraps; a transcript with no error (or no diff) yields `nil`, and the
/// UI is expected to disable the corresponding affordance.
struct TranscriptNavigationAnchors: Sendable, Equatable {
    /// The timeline-item id of the most recent error turn, or `nil` if the transcript has none.
    var lastErrorAnchorID: String?
    /// The timeline-item id of the most recent diff turn, or `nil` if the transcript has none.
    var lastDiffAnchorID: String?

    init(lastErrorAnchorID: String? = nil, lastDiffAnchorID: String? = nil) {
        self.lastErrorAnchorID = lastErrorAnchorID
        self.lastDiffAnchorID = lastDiffAnchorID
    }

    var hasError: Bool { lastErrorAnchorID != nil }
    var hasDiff: Bool { lastDiffAnchorID != nil }

    static func derive(from transcript: TranscriptSurface) -> TranscriptNavigationAnchors {
        derive(timeline: transcript.timelineItems)
    }

    static func derive(timeline: [TranscriptTimelineItemSurface]) -> TranscriptNavigationAnchors {
        var lastError: String?
        var lastDiff: String?
        // Single forward pass; the last hit in timeline order is the most recent, so we simply
        // overwrite. (Reverse-find would be equivalent but this keeps one clear traversal.)
        for item in timeline {
            guard item.kind == .toolCard, let card = item.toolCard else { continue }
            if isErrorCard(card) {
                lastError = item.id
            }
            if isDiffCard(card) {
                lastDiff = item.id
            }
        }
        return TranscriptNavigationAnchors(lastErrorAnchorID: lastError, lastDiffAnchorID: lastDiff)
    }

    /// A tool card counts as an **error** when its run failed. `ToolCardStatus.failed` is set by
    /// the reducer for a nonzero-exit shell run, a tool that threw, etc. — the single source of
    /// truth for "this step went wrong", so we key off it rather than sniffing output text.
    static func isErrorCard(_ card: ToolCardState) -> Bool {
        card.status == .failed
    }

    /// A tool card counts as a **diff** when its tool rewrote tracked file **content in the working
    /// tree** — `apply_patch`, the `revert_turn` reverse-patch, `file.write`, `git.restore`, or
    /// `git.restore_hunk`. This matches the affordance's promise ("most recent file write/patch").
    ///
    /// Classification delegates to the single source of truth
    /// (`WorkspaceTurnRevertPlanner.isDiffProducingTool` / `.workingTreeDiffToolNames`), which the
    /// HTML/Playwright harness mirrors id-for-id and `WorkspaceTurnRevertDiffToolParityTests`
    /// guards. It deliberately EXCLUDES repo/remote ops that leave working-tree bytes unchanged —
    /// `git.pr.*`, `git.push`, `git.commit`/`git.stage`/`git.stage_hunk`, `git.worktree.*` — and the
    /// opaque `shell.run`, so "Last diff" never jumps to an "add PR reviewers" or "push branch" card.
    ///
    /// We also do NOT infer "diff" from file/path artifacts: read-only tools
    /// (`host.file.read` / `host.file.list` / `host.file.search`) all emit absolute-path artifacts
    /// that `ToolArtifactValueClassifier` labels `.file`, so an artifact fallback would light up
    /// "Last diff" in read-only sessions and, since `derive()` keeps the last hit in timeline
    /// order, would jump `[apply_patch, then file.read]` to the READ.
    static func isDiffCard(_ card: ToolCardState) -> Bool {
        isDiffProducingToolName(card.title)
    }

    /// Whether a tool by this raw id rewrote working-tree file content. `derive()` only calls this
    /// for `.toolCard` items, so the input is a tool id. Tolerant of surrounding whitespace and a
    /// de-prefixed display title (`apply_patch` as well as `host.apply_patch`); the shared set holds
    /// only fully-qualified `host.*` ids, so a non-tool title cannot false-positive.
    static func isDiffProducingToolName(_ rawTitle: String) -> Bool {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return canonicalToolNameCandidates(trimmed).contains(where: WorkspaceTurnRevertPlanner.isDiffProducingTool)
    }

    /// The raw title as-is plus a `host.`-prefixed variant, so a de-prefixed display title still
    /// resolves against the fully-qualified tool registry (`apply_patch` → `host.apply_patch`).
    private static func canonicalToolNameCandidates(_ trimmed: String) -> [String] {
        guard !trimmed.isEmpty else { return [] }
        if trimmed.hasPrefix("host.") {
            return [trimmed]
        }
        return [trimmed, "host.\(trimmed)"]
    }
}
