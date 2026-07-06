import Foundation

/// The user's triage decision for a thread, defaulting to `pending`.
public enum ThreadTriageState: String, Codable, Sendable, Hashable {
    case pending
    case acknowledged
    case dismissed

    public var isActionable: Bool { self == .pending }
}

/// Persists a `ThreadTriageState` onto a thread as a `.notice` event.
public enum ThreadTriageRecord {
    public static let eventSummary = "thread-triage-state"

    private static let store = ThreadNoticeRecordStore<Payload>(eventSummary: eventSummary)

    public struct Payload: Codable, Sendable, Hashable {
        public var state: ThreadTriageState
        public var verdictRecordID: UUID?

        public init(state: ThreadTriageState, verdictRecordID: UUID? = nil) {
            self.state = state
            self.verdictRecordID = verdictRecordID
        }
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        store.isRecord(event)
    }

    public static func event(for state: ThreadTriageState, verdictRecordID: UUID?) -> ThreadEvent? {
        store.event(for: Payload(state: state, verdictRecordID: verdictRecordID))
    }

    public static func latestPayload(in thread: ChatThread) -> Payload? {
        store.latestPayload(in: thread)
    }

    public static func current(in thread: ChatThread) -> ThreadTriageState {
        latestPayload(in: thread)?.state ?? .pending
    }

    public static func needsAttention(in thread: ChatThread) -> Bool {
        guard let payload = latestPayload(in: thread), !payload.state.isActionable else {
            return true
        }
        return payload.verdictRecordID != RunIntegrityRecord.latestRecordID(in: thread)
    }

    @discardableResult
    public static func set(_ state: ThreadTriageState, on thread: inout ChatThread) -> Bool {
        let verdictRecordID = RunIntegrityRecord.latestRecordID(in: thread)
        // Idempotent: an unchanged decision does not append a new event or bump the thread's recency.
        if let existing = latestPayload(in: thread),
           existing.state == state,
           existing.verdictRecordID == verdictRecordID {
            return false
        }
        return store.upsert(Payload(state: state, verdictRecordID: verdictRecordID), into: &thread) != nil
    }
}

/// Persisted "last viewed" state used to compute morning-triage unseen-turn counts.
public enum ThreadReturnWatermarkRecord {
    public static let eventSummary = "thread-return-watermark"

    private static let store = ThreadNoticeRecordStore<Payload>(eventSummary: eventSummary)

    public struct Payload: Codable, Sendable, Hashable {
        public var lastSeenItemID: String?

        public init(lastSeenItemID: String?) {
            self.lastSeenItemID = lastSeenItemID
        }
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        store.isRecord(event)
    }

    public static func timelineID(for message: ChatMessage) -> String {
        "message-\(message.id.uuidString)"
    }

    public static func messageTimelineIDs(for thread: ChatThread) -> [String] {
        thread.messages.filter { $0.role != .tool }.map(timelineID(for:))
    }

    public static func lastSeenItemID(in thread: ChatThread) -> String? {
        store.latestPayload(in: thread)?.lastSeenItemID
    }

    public static func unseenCount(in thread: ChatThread) -> Int {
        guard let lastSeen = lastSeenItemID(in: thread) else { return 0 }
        let ids = messageTimelineIDs(for: thread)
        guard let seenIndex = ids.firstIndex(of: lastSeen) else { return 0 }
        let firstUnseen = ids.index(after: seenIndex)
        guard firstUnseen < ids.endIndex else { return 0 }
        return ids.distance(from: firstUnseen, to: ids.endIndex)
    }

    @discardableResult
    public static func markSeen(_ thread: inout ChatThread) -> Bool {
        guard let tail = messageTimelineIDs(for: thread).last else { return false }
        guard lastSeenItemID(in: thread) != tail else { return false }
        // Pure view-state: marking a thread seen must NOT bump updatedAt (it would reorder the thread
        // in a recency-sorted list just for having been looked at).
        return store.upsert(Payload(lastSeenItemID: tail), into: &thread, bumpsUpdatedAt: false) != nil
    }
}
