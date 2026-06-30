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
    /// Tool calls (other than `apply_patch`) that can change the working tree, so a turn
    /// containing them is flagged as having edits a reverse-patch can't undo. Listed by
    /// `ToolDefinition` constant so the set tracks tool renames. Update this whenever a new
    /// file-mutating tool is added — under-reporting here would make the undo's scope a lie.
    static let mutatingNonApplyToolNames: Set<String> = [
        ToolDefinition.fileWrite.name,
        ToolDefinition.shellRun.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitRestoreHunk.name,
        ToolDefinition.gitCommit.name,
        ToolDefinition.mcpCall.name
    ]

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
            } else if mutatingNonApplyToolNames.contains(call.name) {
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

    private static func decodeCall(_ payloadJSON: String?) -> ToolCall? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(ToolCall.self, from: payloadJSON)
    }

    private static func patch(from call: ToolCall) -> String? {
        (try? ToolArguments(call.argumentsJSON))?.string("patch")
    }
}
