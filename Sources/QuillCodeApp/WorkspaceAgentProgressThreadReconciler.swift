import Foundation
import QuillCodeCore

/// Applies presentation-cadence agent snapshots without making the model retain the producer's
/// large transcript buffers. Agent histories normally append or update their current tail; the
/// identified-array reconciliation also handles truncation and structural replacement exactly.
struct WorkspaceAgentProgressThreadMutation: Sendable, Hashable {
    enum MessageMutation: Sendable, Hashable {
        case unchanged
        case replacedAssistantTail(messageID: UUID)
        case appendedAssistantTail(messageID: UUID)
        case rebuild
    }

    var threadID: UUID
    var messageMutation: MessageMutation
    var eventsAffectTranscript: Bool
    var contextAffectsTranscript: Bool
}

enum WorkspaceAgentProgressThreadReconciler {
    static func reconcile(
        _ snapshot: ChatThread,
        into live: inout ChatThread
    ) -> WorkspaceAgentProgressThreadMutation {
        precondition(snapshot.id == live.id)

        let contextAffectsTranscript = live.projectID != snapshot.projectID
        let previousLastMessage = live.messages.last
        live.title = snapshot.title
        live.projectID = snapshot.projectID
        live.mode = snapshot.mode
        live.model = snapshot.model
        live.personality = snapshot.personality
        let messageSummary = reconcile(snapshot.messages, into: &live.messages)
        _ = reconcile(snapshot.modelContextItems, into: &live.modelContextItems)
        var tailHasPersistedMessageEvent = false
        let eventSummary = reconcile(
            snapshot.events,
            into: &live.events,
            changeAffectsTranscript: { previous, next in
                previous.kind.affectsTranscriptProjection || next.kind.affectsTranscriptProjection
            },
            inspectSnapshotElement: { event in
                guard event.kind == .message else { return }
                tailHasPersistedMessageEvent = tailHasPersistedMessageEvent
                    || event.summary == previousLastMessage?.content
                    || event.summary == snapshot.messages.last?.content
            }
        )
        _ = reconcile(snapshot.subagentRuns, into: &live.subagentRuns)
        live.isPinned = snapshot.isPinned
        live.isArchived = snapshot.isArchived
        live.createdAt = snapshot.createdAt
        live.updatedAt = snapshot.updatedAt
        live.worktree = snapshot.worktree
        live.pullRequest = snapshot.pullRequest
        live.forkParentThreadID = snapshot.forkParentThreadID
        live.forkAnchorTurnMessageID = snapshot.forkAnchorTurnMessageID
        live.runtimeContext = snapshot.runtimeContext

        // instructions, memories, goal, drafts, attachments, and the follow-up queue are owned by
        // the live workspace model and may change after the agent captured its send-start snapshot.
        let messageMutation = messageMutation(
            from: messageSummary,
            previousLastMessage: previousLastMessage,
            messages: snapshot.messages
        )
        let persistedTailEventRequiresRebuild: Bool
        switch messageMutation {
        case .replacedAssistantTail, .appendedAssistantTail:
            persistedTailEventRequiresRebuild = tailHasPersistedMessageEvent
        case .unchanged, .rebuild:
            persistedTailEventRequiresRebuild = false
        }
        return WorkspaceAgentProgressThreadMutation(
            threadID: snapshot.id,
            messageMutation: messageMutation,
            eventsAffectTranscript: eventSummary.affectsTranscript || persistedTailEventRequiresRebuild,
            contextAffectsTranscript: contextAffectsTranscript
        )
    }

    private struct ArrayMutationSummary {
        var previousCount: Int
        var currentCount: Int
        var changedCount = 0
        var onlyChangedIndex: Int?
        var didReplaceStructure = false
        var affectsTranscript = false
    }

    private static func reconcile<Element>(
        _ snapshot: [Element],
        into live: inout [Element],
        changeAffectsTranscript: (Element, Element) -> Bool = { _, _ in false },
        inspectSnapshotElement: (Element) -> Void = { _ in }
    ) -> ArrayMutationSummary where Element: Identifiable & Equatable, Element.ID: Equatable {
        let previousCount = live.count
        var summary = ArrayMutationSummary(previousCount: previousCount, currentCount: snapshot.count)
        let overlapCount = min(live.count, snapshot.count)
        for index in 0..<overlapCount {
            inspectSnapshotElement(snapshot[index])
            guard live[index].id == snapshot[index].id else {
                summary.didReplaceStructure = true
                summary.affectsTranscript = true
                replaceDetached(&live, with: snapshot)
                return summary
            }
            if live[index] != snapshot[index] {
                summary.changedCount += 1
                summary.onlyChangedIndex = summary.changedCount == 1 ? index : nil
                summary.affectsTranscript = summary.affectsTranscript
                    || changeAffectsTranscript(live[index], snapshot[index])
                live[index] = snapshot[index]
            }
        }

        if snapshot.count > live.count {
            for element in snapshot[live.count...] {
                inspectSnapshotElement(element)
                summary.affectsTranscript = summary.affectsTranscript
                    || changeAffectsTranscript(element, element)
            }
            live.append(contentsOf: snapshot[live.count...])
        } else if snapshot.count < live.count {
            for element in live[snapshot.count...] {
                summary.affectsTranscript = summary.affectsTranscript
                    || changeAffectsTranscript(element, element)
            }
            live.removeLast(live.count - snapshot.count)
        }
        return summary
    }

    private static func messageMutation(
        from summary: ArrayMutationSummary,
        previousLastMessage: ChatMessage?,
        messages: [ChatMessage]
    ) -> WorkspaceAgentProgressThreadMutation.MessageMutation {
        guard !summary.didReplaceStructure else { return .rebuild }
        if summary.previousCount == summary.currentCount {
            guard summary.changedCount > 0 else { return .unchanged }
            guard summary.changedCount == 1,
                  summary.onlyChangedIndex == messages.indices.last,
                  let last = messages.last,
                  previousLastMessage?.role == .assistant,
                  last.role == .assistant
            else {
                return .rebuild
            }
            return .replacedAssistantTail(messageID: last.id)
        }
        guard summary.changedCount == 0,
              summary.currentCount == summary.previousCount + 1,
              let last = messages.last,
              last.role == .assistant
        else {
            return .rebuild
        }
        return .appendedAssistantTail(messageID: last.id)
    }

    private static func replaceDetached<Element>(_ live: inout [Element], with snapshot: [Element]) {
        live.removeAll(keepingCapacity: true)
        live.append(contentsOf: snapshot)
    }
}

private extension ThreadEventKind {
    var affectsTranscriptProjection: Bool {
        switch self {
        case .message, .toolQueued, .toolRunning, .toolProgress, .toolCompleted, .toolFailed,
             .approvalRequested, .approvalDecided:
            return true
        case .messageFeedback, .reviewComment, .notice:
            return false
        }
    }
}
