import Foundation

/// Scaffolding for a "single latest record" persisted onto a thread as a `.notice` event: one
/// well-known `summary` marker identifies the record among a thread's events, and there is at most one
/// live instance (an upsert removes any prior copy before appending). Several features layer their own
/// payload on this same shape — the run-integrity verdict, the triage decision, the return watermark —
/// so the marker/scan/decode/upsert mechanics live here once instead of being re-implemented per type.
///
/// Each owning type keeps its own public API and domain logic (scanning, dedup guards, derived helpers)
/// and delegates only the event bookkeeping to a `ThreadNoticeRecordStore` instance.
public struct ThreadNoticeRecordStore<Payload: Codable & Sendable>: Sendable {
    public let eventSummary: String

    public init(eventSummary: String) {
        self.eventSummary = eventSummary
    }

    /// Whether an event is this store's record (a `.notice` carrying the well-known summary marker).
    public func isRecord(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary == eventSummary
    }

    /// The most recent record EVENT on a thread (for callers that need its stable id), or nil.
    public func latestEvent(in thread: ChatThread) -> ThreadEvent? {
        for event in thread.events.reversed() where isRecord(event) {
            return event
        }
        return nil
    }

    /// The most recent record's decoded payload, or nil if none was recorded (or it fails to decode).
    public func latestPayload(in thread: ChatThread) -> Payload? {
        latestEvent(in: thread)?
            .payloadJSON
            .flatMap { try? JSONHelpers.decode(Payload.self, from: $0) }
    }

    /// The notice event carrying an encoded payload, or nil only if encoding fails.
    public func event(for payload: Payload) -> ThreadEvent? {
        guard let payloadJSON = try? JSONHelpers.encodePretty(payload) else { return nil }
        return ThreadEvent(kind: .notice, summary: eventSummary, payloadJSON: payloadJSON)
    }

    /// Replaces any existing record with a fresh one. Returns the appended event, or nil if encoding
    /// failed (in which case the thread is left with no record, matching the prior per-type behavior).
    /// `bumpsUpdatedAt` is false for records that are pure view-state (the return watermark) so marking
    /// a thread seen does not reorder it in a recency-sorted list.
    @discardableResult
    public func upsert(
        _ payload: Payload,
        into thread: inout ChatThread,
        bumpsUpdatedAt: Bool = true
    ) -> ThreadEvent? {
        thread.events.removeAll(where: isRecord)
        guard let event = event(for: payload) else { return nil }
        thread.events.append(event)
        if bumpsUpdatedAt {
            thread.updatedAt = Date()
        }
        return event
    }
}
