import Foundation
import QuillCodeCore
import QuillCodeTools

/// The recorded `apply_patch` edits of a single agent turn that can be reverse-applied to
/// undo exactly that turn's file changes. A turn with no `apply_patch` edits yields no plan
/// (so the UI never offers an undo it can't honor).
public struct TurnRevertPlan: Sendable, Hashable {
    /// The user message that began the turn.
    public let turnMessageID: UUID
    /// The turn's `apply_patch` patch strings, in chronological (applied) order.
    public let patches: [String]
    /// Whether the turn ALSO wrote files outside `apply_patch` (shell/file-write), which a
    /// diff-based revert cannot undo — surfaced so the UI can disclose the gap honestly.
    public let hasNonApplyPatchEdits: Bool

    public init(turnMessageID: UUID, patches: [String], hasNonApplyPatchEdits: Bool) {
        self.turnMessageID = turnMessageID
        self.patches = patches
        self.hasNonApplyPatchEdits = hasNonApplyPatchEdits
    }
}

/// Derives per-turn revert plans from a thread's recorded events. A "turn" is the span from
/// a user message to the next user message; there is no turn id in the model, so events are
/// attributed to the latest user message at-or-before their timestamp (the same chronology
/// the transcript builder renders by). Pure and synchronous — no git, no side effects.
public enum WorkspaceTurnRevertPlanner {
    /// The tool id recorded for a reverse-patch turn revert (see `runTurnRevert`). It is a dynamic
    /// tool with no static `ToolDefinition`, so it is named once here and reused everywhere that
    /// must recognize it (the recorder and the transcript's "Last diff" classifier) rather than
    /// duplicating the literal.
    public static let revertTurnToolName = "host.git.revert_turn"

    /// The risk class of every statically-defined tool, so a turn's non-`apply_patch` edits are
    /// detected by SAFETY rather than a hand-maintained name list that silently rots the moment a new
    /// mutating tool is added (the old denylist provably omitted, e.g., `host.git.pr.checkout` and the
    /// computer-use tools — a turn using them reported a clean full undo it could not deliver).
    private static let toolRiskByName: [String: ToolRiskClass] = Dictionary(
        ToolRouter.definitions.map { ($0.name, $0.risk) },
        uniquingKeysWith: { existing, _ in existing }
    )

    /// Whether a statically-registered tool exists for this name (i.e. it is not a dynamic/MCP
    /// tool). Used to keep the "Last diff" classifier from treating arbitrary non-`host.*` card
    /// titles as mutating just because they are unknown.
    static func isRegisteredTool(_ name: String) -> Bool {
        toolRiskByName[name] != nil
    }

    /// The tool ids whose run rewrites tracked file **content in the working tree** — i.e. produces
    /// a `git diff`. This is the precise scope of the transcript's "Last diff" affordance (doc:
    /// "most recent file write/patch"), NOT the broader "any non-read side effect": it deliberately
    /// EXCLUDES repo/remote ops that leave working-tree file bytes unchanged —
    /// - most `host.git.pr.*` (PR metadata: reviewers, labels, comments, merge, review threads),
    /// - `host.git.push` (uploads already-committed history),
    /// - `host.git.commit` / `host.git.stage` / `host.git.stage_hunk` (record/stage content that is
    ///   already on disk; they do not change working-tree file bytes),
    /// - `host.git.worktree.*` (create/remove/prune a worktree — not a content diff),
    /// - `host.shell.run` (opaque; may or may not write files, so we do not claim it as a diff).
    ///
    /// `host.git.pr.checkout` is the one PR tool that IS included: it runs `gh pr checkout`, which
    /// switches the working tree to the PR's head branch and wholesale-rewrites every differing file
    /// on disk — a real working-tree content change, and often the single most impactful one in a
    /// PR-review flow. (The rest of `host.git.pr.*` only touch PR metadata.)
    ///
    /// This is the SINGLE SOURCE OF TRUTH shared by the native classifier and, mirrored id-for-id,
    /// the HTML/Playwright harness. `WorkspaceTurnRevertDiffToolParityTests` enumerates every
    /// registered tool plus the dynamic ids and asserts membership matches the harness set, so a
    /// future divergence (a new file-mutating tool added to one side only) fails CI rather than
    /// silently drifting.
    ///
    /// Note this is a distinct, narrower concept from ``isMutatingNonApplyTool`` (which the revert
    /// planner uses to decide whether a turn's undo is *partial* — there, over-claiming mutation is
    /// the safe direction; here, precision to file-content changes is what the label promises).
    public static let workingTreeDiffToolNames: Set<String> = [
        ToolDefinition.applyPatch.name,             // host.apply_patch
        revertTurnToolName,                         // host.git.revert_turn (dynamic; reverse-applies a patch)
        ToolDefinition.fileWrite.name,              // host.file.write
        ToolDefinition.gitRestore.name,             // host.git.restore
        ToolDefinition.gitRestoreHunk.name,         // host.git.restore_hunk
        ToolDefinition.gitPullRequestCheckout.name  // host.git.pr.checkout (switches branch → rewrites files on disk)
    ]

    /// Whether a tool run rewrote tracked file content in the working tree — the "Last diff"
    /// predicate. See ``workingTreeDiffToolNames`` for the exact set and rationale.
    public static func isDiffProducingTool(_ name: String) -> Bool {
        workingTreeDiffToolNames.contains(name)
    }

    /// Whether a tool call other than `apply_patch` changed state that a reverse-patch of this turn's
    /// `apply_patch` edits cannot undo — a mutating local-tree change, or a remote/side effect the
    /// revert won't reverse. Classified by risk (anything not read-only is mutating), so it is
    /// correct-by-construction for every current and future tool. Unknown/dynamic tools (MCP, computer
    /// use, a prior `host.git.revert_turn`) are treated as mutating: over-warning that the undo is
    /// partial is safe; under-warning would make the undo's scope a lie.
    static func isMutatingNonApplyTool(_ name: String) -> Bool {
        guard name != ToolDefinition.applyPatch.name else { return false }
        guard let risk = toolRiskByName[name] else { return true }
        return risk != .read
    }

    public static func plans(for thread: ChatThread) -> [TurnRevertPlan] {
        let userMessages = thread.messages
            .filter { $0.role == .user }
            .sorted { $0.createdAt < $1.createdAt }
        guard !userMessages.isEmpty else { return [] }

        func turnID(at date: Date) -> UUID? {
            userMessages.last(where: { $0.createdAt <= date })?.id
        }

        var patchesByTurn: [UUID: [String]] = [:]
        var hasNonApplyByTurn: [UUID: Bool] = [:]
        var turnOrder: [UUID] = []

        // Sort by createdAt so the within-turn patch order matches the turn-attribution
        // chronology (the executor reverse-applies newest-first, so order is load-bearing).
        let queuedEvents = thread.events
            .filter { $0.kind == .toolQueued }
            .sorted { $0.createdAt < $1.createdAt }
        for event in queuedEvents {
            guard let turn = turnID(at: event.createdAt),
                  let call = decodeCall(event.payloadJSON)
            else { continue }

            if call.name == ToolDefinition.applyPatch.name {
                guard let patch = patch(from: call),
                      !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { continue }
                if patchesByTurn[turn] == nil { turnOrder.append(turn) }
                patchesByTurn[turn, default: []].append(patch)
            } else if isMutatingNonApplyTool(call.name) {
                hasNonApplyByTurn[turn] = true
            }
        }

        return turnOrder.compactMap { turn in
            guard let patches = patchesByTurn[turn], !patches.isEmpty else { return nil }
            return TurnRevertPlan(
                turnMessageID: turn,
                patches: patches,
                hasNonApplyPatchEdits: hasNonApplyByTurn[turn] ?? false
            )
        }
    }

    /// The revert plan for one turn (its starting user message), or nil when that turn made
    /// no `apply_patch` edits.
    public static func plan(for turnMessageID: UUID, in thread: ChatThread) -> TurnRevertPlan? {
        plans(for: thread).first { $0.turnMessageID == turnMessageID }
    }

    /// Whether this thread's run changed files at all — an `apply_patch` edit OR any non-read mutating
    /// tool (shell write, git, file write, …). The verification gate uses this to check only after an
    /// edit-bearing run. Reuses the same risk-classified mutation test as the revert-scope flag, so it
    /// can never silently miss a new mutating tool.
    static func threadMadeEdits(_ thread: ChatThread) -> Bool {
        thread.events.contains { event in
            guard event.kind == .toolQueued, let call = decodeCall(event.payloadJSON) else { return false }
            return call.name == ToolDefinition.applyPatch.name || isMutatingNonApplyTool(call.name)
        }
    }

    private static func decodeCall(_ payloadJSON: String?) -> ToolCall? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(ToolCall.self, from: payloadJSON)
    }

    private static func patch(from call: ToolCall) -> String? {
        (try? ToolArguments(call.argumentsJSON))?.string("patch")
    }
}
