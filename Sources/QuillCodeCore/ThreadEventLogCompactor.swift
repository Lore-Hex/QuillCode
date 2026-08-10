import Foundation

/// Keeps presentation-only streaming snapshots from turning a thread's durable event history into
/// a token log. Meaningful events remain untouched; only consecutive reasoning notices coalesce.
public enum ThreadEventLogCompactor {
    public static let reasoningNoticePrefix = "Thinking:"

    public static func compact(_ events: [ThreadEvent]) -> [ThreadEvent] {
        guard events.count > 1 else { return events }
        guard containsConsecutiveReasoningNotices(events) else { return events }

        var compacted: [ThreadEvent] = []
        compacted.reserveCapacity(events.count)
        var pendingReasoningNotice: ThreadEvent?

        for event in events {
            if isReasoningNotice(event) {
                pendingReasoningNotice = event
                continue
            }

            if let pendingReasoningNotice {
                compacted.append(pendingReasoningNotice)
            }
            pendingReasoningNotice = nil
            compacted.append(event)
        }

        if let pendingReasoningNotice {
            compacted.append(pendingReasoningNotice)
        }
        return compacted
    }

    public static func compact(_ thread: ChatThread) -> ChatThread {
        var thread = thread
        thread.events = compact(thread.events)
        return thread
    }

    private static func isReasoningNotice(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary.hasPrefix(reasoningNoticePrefix)
    }

    private static func containsConsecutiveReasoningNotices(_ events: [ThreadEvent]) -> Bool {
        var previousWasReasoning = false
        for event in events {
            let currentIsReasoning = isReasoningNotice(event)
            if previousWasReasoning && currentIsReasoning {
                return true
            }
            previousWasReasoning = currentIsReasoning
        }
        return false
    }
}
