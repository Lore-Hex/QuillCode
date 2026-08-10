import Foundation
import QuillCodeCore

enum WorkspaceAgentTranscriptRefreshPlan: Sendable, Hashable {
    case reuse(selectedThreadID: UUID?)
    case replaceAssistantTail(threadID: UUID, messageID: UUID)
    case appendAssistantTail(threadID: UUID, messageID: UUID)
    case rebuild

    func combined(with next: Self) -> Self {
        switch (self, next) {
        case (.rebuild, _), (_, .rebuild):
            return .rebuild
        case let (.reuse(previousID), .reuse(nextID)):
            return previousID == nextID ? self : .rebuild
        case let (.reuse(selectedID), .replaceAssistantTail(threadID, _)),
             let (.reuse(selectedID), .appendAssistantTail(threadID, _)):
            return selectedID == threadID ? next : .rebuild
        case let (.replaceAssistantTail(threadID, _), .reuse(selectedID)),
             let (.appendAssistantTail(threadID, _), .reuse(selectedID)):
            return selectedID == threadID ? self : .rebuild
        case let (
            .replaceAssistantTail(previousThreadID, previousMessageID),
            .replaceAssistantTail(nextThreadID, nextMessageID)
        ):
            return previousThreadID == nextThreadID && previousMessageID == nextMessageID
                ? self
                : .rebuild
        case let (
            .appendAssistantTail(previousThreadID, previousMessageID),
            .replaceAssistantTail(nextThreadID, nextMessageID)
        ):
            return previousThreadID == nextThreadID && previousMessageID == nextMessageID
                ? self
                : .rebuild
        case (.replaceAssistantTail, .appendAssistantTail),
             (.appendAssistantTail, .appendAssistantTail):
            return .rebuild
        }
    }

    func updatingTranscript(
        _ previous: TranscriptSurface,
        for thread: ChatThread?
    ) -> TranscriptSurface? {
        switch self {
        case .rebuild:
            return nil
        case .reuse(let selectedThreadID):
            guard thread?.id == selectedThreadID else { return nil }
            return previous
        case .replaceAssistantTail(let threadID, let messageID):
            guard let message = thread?.messages.last,
                  thread?.id == threadID,
                  message.id == messageID,
                  message.role == .assistant,
                  previous.messages.last?.id == messageID,
                  previous.timelineItems.last?.message?.id == messageID
            else {
                return nil
            }
            let messageSurface = MessageSurface(message: message)
            var next = previous
            next.messages[next.messages.index(before: next.messages.endIndex)] = messageSurface
            next.timelineItems[next.timelineItems.index(before: next.timelineItems.endIndex)] = .message(messageSurface)
            return next
        case .appendAssistantTail(let threadID, let messageID):
            guard let message = thread?.messages.last,
                  thread?.id == threadID,
                  message.id == messageID,
                  message.role == .assistant,
                  previous.messages.last?.id != messageID
            else {
                return nil
            }
            let messageSurface = MessageSurface(message: message)
            var next = previous
            next.messages.append(messageSurface)
            next.timelineItems.append(.message(messageSurface))
            return next
        }
    }
}

struct WorkspaceAgentTranscriptRefreshTracker: Sendable, Hashable {
    private struct PublishedSelection: Sendable, Hashable {
        var threadID: UUID?
    }

    private var publishedSelection: PublishedSelection?
    private var pendingPlan: WorkspaceAgentTranscriptRefreshPlan?

    mutating func didPublishAuthoritativeSurface(selectedThreadID: UUID?) {
        publishedSelection = PublishedSelection(threadID: selectedThreadID)
        pendingPlan = nil
    }

    mutating func record(
        _ mutation: WorkspaceAgentProgressThreadMutation,
        selectedThreadID: UUID?
    ) {
        guard let publishedSelection,
              publishedSelection.threadID == selectedThreadID
        else {
            pendingPlan = .rebuild
            return
        }

        let next: WorkspaceAgentTranscriptRefreshPlan
        if mutation.threadID != selectedThreadID {
            next = .reuse(selectedThreadID: selectedThreadID)
        } else if mutation.eventsAffectTranscript || mutation.contextAffectsTranscript {
            next = .rebuild
        } else {
            switch mutation.messageMutation {
            case .unchanged:
                next = .reuse(selectedThreadID: selectedThreadID)
            case .replacedAssistantTail(let messageID):
                next = .replaceAssistantTail(threadID: mutation.threadID, messageID: messageID)
            case .appendedAssistantTail(let messageID):
                next = .appendAssistantTail(threadID: mutation.threadID, messageID: messageID)
            case .rebuild:
                next = .rebuild
            }
        }
        pendingPlan = pendingPlan.map { $0.combined(with: next) } ?? next
    }

    mutating func consume(selectedThreadID: UUID?) -> WorkspaceAgentTranscriptRefreshPlan {
        defer {
            publishedSelection = PublishedSelection(threadID: selectedThreadID)
            pendingPlan = nil
        }
        guard let publishedSelection,
              publishedSelection.threadID == selectedThreadID
        else {
            return .rebuild
        }
        return pendingPlan ?? .rebuild
    }
}
