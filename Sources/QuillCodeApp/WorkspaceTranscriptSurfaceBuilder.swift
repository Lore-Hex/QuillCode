import Foundation
import QuillCodeCore

struct WorkspaceTranscriptSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread
    /// Whether to offer per-turn revert affordances. False for remote projects, where the
    /// reverse-patch engine (local `git apply`) cannot operate on the remote tree.
    var allowsRevert: Bool = true

    func messageSurfaces() -> [MessageSurface] {
        let revertByMessageID = allowsRevert ? Self.revertByMessageID(for: thread) : [:]
        return thread.messages
            .filter { $0.role != .tool }
            .map { message in
                MessageSurface(message: message, revert: revertByMessageID[message.id])
            }
    }

    /// Maps each revertable turn's starting user-message id to its revert affordance.
    static func revertByMessageID(for thread: ChatThread) -> [UUID: MessageRevertSurface] {
        var map: [UUID: MessageRevertSurface] = [:]
        for plan in WorkspaceTurnRevertPlanner.plans(for: thread) {
            map[plan.turnMessageID] = MessageRevertSurface(
                turnMessageID: plan.turnMessageID,
                hasNonApplyPatchEdits: plan.hasNonApplyPatchEdits
            )
        }
        return map
    }

    func toolCards() -> [ToolCardState] {
        var reducer = WorkspaceToolCardEventReducer<[ToolCardState]>.toolCardList()
        for event in thread.events {
            reducer.apply(event)
        }

        return reducer.state
    }

    func timelineItems() -> [TranscriptTimelineItemSurface] {
        guard !thread.events.isEmpty else {
            return messageSurfaces().map(TranscriptTimelineItemSurface.message)
                + toolCards().map(TranscriptTimelineItemSurface.toolCard)
        }

        let revertByMessageID = allowsRevert ? Self.revertByMessageID(for: thread) : [:]
        var consumedMessageIDs = Set<UUID>()
        var reducer = WorkspaceToolCardEventReducer<[TranscriptTimelineItemSurface]>.timeline()

        func appendMessage(matching summary: String) {
            guard let message = thread.messages.first(where: {
                !consumedMessageIDs.contains($0.id) && $0.content == summary
            }) else {
                return
            }
            consumedMessageIDs.insert(message.id)
            reducer.state.append(.message(MessageSurface(message: message, revert: revertByMessageID[message.id])))
        }

        for event in thread.events {
            switch event.kind {
            case .message:
                appendMessage(matching: event.summary)
            case .messageFeedback, .reviewComment, .notice:
                continue
            case .toolQueued, .toolRunning, .toolCompleted, .toolFailed, .approvalRequested, .approvalDecided:
                reducer.apply(event)
            }
        }

        for message in thread.messages where message.role != .tool && !consumedMessageIDs.contains(message.id) {
            reducer.state.append(.message(MessageSurface(message: message, revert: revertByMessageID[message.id])))
        }
        return reducer.state
    }
}
