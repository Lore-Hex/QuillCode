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

    public struct Payload: Codable, Sendable, Hashable {
        public var state: ThreadTriageState
        public var verdictRecordID: UUID?

        public init(state: ThreadTriageState, verdictRecordID: UUID? = nil) {
            self.state = state
            self.verdictRecordID = verdictRecordID
        }
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary == eventSummary
    }

    public static func event(for state: ThreadTriageState, verdictRecordID: UUID?) -> ThreadEvent? {
        let payload = Payload(state: state, verdictRecordID: verdictRecordID)
        guard let payloadJSON = try? JSONHelpers.encodePretty(payload) else { return nil }
        return ThreadEvent(kind: .notice, summary: eventSummary, payloadJSON: payloadJSON)
    }

    public static func latestPayload(in thread: ChatThread) -> Payload? {
        for event in thread.events.reversed() where isRecord(event) {
            if let payloadJSON = event.payloadJSON,
               let payload = try? JSONHelpers.decode(Payload.self, from: payloadJSON) {
                return payload
            }
        }
        return nil
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
        if let existing = latestPayload(in: thread),
           existing.state == state,
           existing.verdictRecordID == verdictRecordID {
            return false
        }
        thread.events.removeAll(where: isRecord)
        if let event = event(for: state, verdictRecordID: verdictRecordID) {
            thread.events.append(event)
            thread.updatedAt = Date()
            return true
        }
        return false
    }
}

/// Persisted "last viewed" state used to compute morning-triage unseen-turn counts.
public enum ThreadReturnWatermarkRecord {
    public static let eventSummary = "thread-return-watermark"

    public struct Payload: Codable, Sendable, Hashable {
        public var lastSeenItemID: String?

        public init(lastSeenItemID: String?) {
            self.lastSeenItemID = lastSeenItemID
        }
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary == eventSummary
    }

    public static func timelineID(for message: ChatMessage) -> String {
        "message-\(message.id.uuidString)"
    }

    public static func messageTimelineIDs(for thread: ChatThread) -> [String] {
        thread.messages.filter { $0.role != .tool }.map(timelineID(for:))
    }

    public static func lastSeenItemID(in thread: ChatThread) -> String? {
        for event in thread.events.reversed() where isRecord(event) {
            if let payloadJSON = event.payloadJSON,
               let payload = try? JSONHelpers.decode(Payload.self, from: payloadJSON) {
                return payload.lastSeenItemID
            }
        }
        return nil
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
        thread.events.removeAll(where: isRecord)
        guard let payloadJSON = try? JSONHelpers.encodePretty(Payload(lastSeenItemID: tail)) else {
            return false
        }
        thread.events.append(ThreadEvent(kind: .notice, summary: eventSummary, payloadJSON: payloadJSON))
        return true
    }
}
