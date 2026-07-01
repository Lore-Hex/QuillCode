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
    /// The risk class of every statically-defined tool, so a turn's non-`apply_patch` edits are
    /// detected by SAFETY rather than a hand-maintained name list that silently rots the moment a new
    /// mutating tool is added (the old denylist provably omitted, e.g., `host.git.pr.checkout` and the
    /// computer-use tools — a turn using them reported a clean full undo it could not deliver).
    private static let toolRiskByName: [String: ToolRiskClass] = Dictionary(
        ToolRouter.definitions.map { ($0.name, $0.risk) },
        uniquingKeysWith: { existing, _ in existing }
    )

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
