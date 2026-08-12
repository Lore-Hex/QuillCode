import Foundation
import QuillCodeCore

struct WorkspaceTranscriptProjection: Sendable, Hashable {
    var messages: [MessageSurface]
    var toolCards: [ToolCardState]
    var timelineItems: [TranscriptTimelineItemSurface]

    static let empty = WorkspaceTranscriptProjection(
        messages: [],
        toolCards: [],
        timelineItems: []
    )
}

struct WorkspaceTranscriptSurfaceBuilder: Sendable, Hashable {
    var thread: ChatThread
    /// Whether to offer per-turn revert affordances. False for remote projects, where the
    /// reverse-patch engine (local `git apply`) cannot operate on the remote tree.
    var allowsRevert: Bool = true

    func messageSurfaces() -> [MessageSurface] {
        let revertByMessageID = allowsRevert ? Self.revertByMessageID(for: thread) : [:]
        return Self.messageSurfaces(
            for: thread.messages,
            revertByMessageID: revertByMessageID
        )
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
        WorkspaceArtifactPreviewRetention.hydrate(&reducer.state)
        return reducer.state
    }

    func timelineItems() -> [TranscriptTimelineItemSurface] {
        projection().timelineItems
    }

    /// Builds the three transcript views together so a desktop surface refresh decodes each tool
    /// lifecycle and plans each message revert once. The separate accessors remain for focused
    /// callers that only need one representation.
    func projection() -> WorkspaceTranscriptProjection {
        let revertByMessageID = allowsRevert ? Self.revertByMessageID(for: thread) : [:]
        var visibleSurfaceIndexByMessageIndex = Array(
            repeating: -1,
            count: thread.messages.count
        )
        var visibleMessages: [MessageSurface] = []
        visibleMessages.reserveCapacity(thread.messages.count)
        for index in thread.messages.indices {
            let message = thread.messages[index]
            guard Self.isVisibleTranscriptRole(message.role) else { continue }
            let surface = MessageSurface(
                message: message,
                revert: revertByMessageID[message.id]
            )
            visibleSurfaceIndexByMessageIndex[index] = visibleMessages.count
            visibleMessages.append(surface)
        }

        guard !thread.events.isEmpty else {
            return WorkspaceTranscriptProjection(
                messages: visibleMessages,
                toolCards: [],
                timelineItems: visibleMessages.map(TranscriptTimelineItemSurface.message)
            )
        }

        var messageIndex: WorkspaceTranscriptMessageIndex?
        let estimatedToolCardCount = min(thread.events.count / 3 + 1, 4_096)
        var reducer = WorkspaceToolCardEventReducer.transcriptProjection(
            state: WorkspaceTranscriptProjectionAccumulator(
                toolCardCapacity: estimatedToolCardCount,
                timelineCapacity: visibleMessages.count + estimatedToolCardCount
            )
        )

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
                let visibleSurfaceIndex = visibleSurfaceIndexByMessageIndex[index]
                let surface = visibleSurfaceIndex >= 0
                    ? visibleMessages[visibleSurfaceIndex]
                    : MessageSurface(message: message, revert: revertByMessageID[message.id])
                reducer.state.appendMessage(surface)
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
            let visibleSurfaceIndex = visibleSurfaceIndexByMessageIndex[index]
            if visibleSurfaceIndex >= 0 {
                reducer.state.appendMessage(visibleMessages[visibleSurfaceIndex])
            }
        }
        WorkspaceArtifactPreviewRetention.hydrate(&reducer.state)
        return WorkspaceTranscriptProjection(
            messages: visibleMessages,
            toolCards: reducer.state.toolCards,
            timelineItems: reducer.state.timelineItems
        )
    }

    private static func messageSurfaces(
        for messages: [ChatMessage],
        revertByMessageID: [UUID: MessageRevertSurface]
    ) -> [MessageSurface] {
        messages.compactMap { message in
            guard isVisibleTranscriptRole(message.role) else { return nil }
            return MessageSurface(message: message, revert: revertByMessageID[message.id])
        }
    }

    private static func isVisibleTranscriptRole(_ role: ChatRole) -> Bool {
        role == .user || role == .assistant
    }
}
