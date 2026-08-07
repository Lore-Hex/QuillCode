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
            .filter { Self.isVisibleTranscriptRole($0.role) }
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
        var messageIndex: WorkspaceTranscriptMessageIndex?
        var reducer = WorkspaceToolCardEventReducer<[TranscriptTimelineItemSurface]>.timeline()

        for event in thread.events {
            switch event.kind {
            case .message:
                if messageIndex == nil {
                    messageIndex = WorkspaceTranscriptMessageIndex(messages: thread.messages)
                }
                guard let index = messageIndex?.consumeFirstIndex(matching: event.summary) else {
                    continue
                }
                let message = thread.messages[index]
                reducer.state.append(.message(MessageSurface(
                    message: message,
                    revert: revertByMessageID[message.id]
                )))
            case .messageFeedback, .reviewComment, .notice:
                continue
            case .toolQueued, .toolRunning, .toolProgress, .toolCompleted, .toolFailed,
                 .approvalRequested, .approvalDecided:
                reducer.apply(event)
            }
        }

        for index in thread.messages.indices {
            let message = thread.messages[index]
            guard Self.isVisibleTranscriptRole(message.role),
                  messageIndex?.isConsumed(message.id) != true
            else {
                continue
            }
            reducer.state.append(.message(MessageSurface(message: message, revert: revertByMessageID[message.id])))
        }
        return reducer.state
    }

    private static func isVisibleTranscriptRole(_ role: ChatRole) -> Bool {
        role == .user || role == .assistant
    }
}
