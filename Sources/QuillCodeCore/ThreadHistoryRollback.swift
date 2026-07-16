import Foundation

public struct ThreadHistoryRollbackResult: Sendable, Hashable {
    public var removedTurnCount: Int
    public var removedMessageCount: Int
    public var removedEventCount: Int
    public var removedSubagentRunCount: Int

    public init(
        removedTurnCount: Int = 0,
        removedMessageCount: Int = 0,
        removedEventCount: Int = 0,
        removedSubagentRunCount: Int = 0
    ) {
        self.removedTurnCount = removedTurnCount
        self.removedMessageCount = removedMessageCount
        self.removedEventCount = removedEventCount
        self.removedSubagentRunCount = removedSubagentRunCount
    }
}

/// Removes complete conversation turns without pretending to undo workspace or account side effects.
/// A protocol turn may contain multiple steered user messages, all sharing one persisted `turnID`.
public enum ThreadHistoryRollback {
    @discardableResult
    public static func apply(
        turnCount: UInt32,
        to thread: inout ChatThread,
        updatedAt: Date = Date()
    ) -> ThreadHistoryRollbackResult {
        guard turnCount > 0 else { return ThreadHistoryRollbackResult() }

        let turnStarts = turnStartIndices(in: thread.messages)
        guard let firstTurnStart = turnStarts.first else {
            thread.updatedAt = updatedAt
            return ThreadHistoryRollbackResult()
        }

        let requestedCount = Int(turnCount)
        let removedTurnCount = min(requestedCount, turnStarts.count)
        let cutIndex = requestedCount >= turnStarts.count
            ? firstTurnStart
            : turnStarts[turnStarts.count - requestedCount]
        let cutoff = thread.messages[cutIndex].createdAt
        let messageCount = thread.messages.count - cutIndex
        thread.messages.removeSubrange(cutIndex...)

        let eventCount = thread.events.count
        thread.events.removeAll { event in
            event.createdAt >= cutoff && ModelTokenUsageEvent.record(from: event) == nil
        }

        let subagentRunCount = thread.subagentRuns.count
        thread.subagentRuns.removeAll { $0.createdAt >= cutoff }
        thread.updatedAt = updatedAt

        return ThreadHistoryRollbackResult(
            removedTurnCount: removedTurnCount,
            removedMessageCount: messageCount,
            removedEventCount: eventCount - thread.events.count,
            removedSubagentRunCount: subagentRunCount - thread.subagentRuns.count
        )
    }

    private static func turnStartIndices(in messages: [ChatMessage]) -> [Int] {
        var starts: [Int] = []
        var currentTurnID: String?
        for (index, message) in messages.enumerated() where message.role == .user {
            let turnID = message.turnID ?? message.id.uuidString.lowercased()
            guard turnID != currentTurnID else { continue }
            starts.append(index)
            currentTurnID = turnID
        }
        return starts
    }
}
