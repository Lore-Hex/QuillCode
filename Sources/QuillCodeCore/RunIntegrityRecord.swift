import Foundation

/// Persists a `RunIntegrityReport` onto a thread as a `.notice` event so the badge is stable across
/// reloads. Reuses the notice-event convention already used for other post-hoc annotations.
public enum RunIntegrityRecord {
    /// The well-known summary marker that identifies the integrity notice among a thread's events.
    public static let eventSummary = "run-integrity-report"

    private static let store = ThreadNoticeRecordStore<Payload>(eventSummary: eventSummary)

    /// The Codable payload stored in the notice event's `payloadJSON`.
    public struct Payload: Codable, Sendable, Hashable {
        public var verdict: RunIntegrityVerdict
        public var summary: String

        public init(verdict: RunIntegrityVerdict, summary: String) {
            self.verdict = verdict
            self.summary = summary
        }
    }

    /// Builds the notice event for a report. Returns nil only if encoding somehow fails.
    public static func event(for report: RunIntegrityReport) -> ThreadEvent? {
        store.event(for: Payload(verdict: report.verdict, summary: report.summaryLine))
    }

    /// The most recently recorded integrity verdict on a thread, or nil if none was ever recorded.
    public static func latest(in thread: ChatThread) -> Payload? {
        store.latestPayload(in: thread)
    }

    /// The most recent integrity-record EVENT on a thread (payload + its stable event id), or nil if
    /// none was ever recorded. The event id identifies the specific run that produced this verdict —
    /// `record(into:)` mints a fresh event each run — so downstream features (morning triage) can tell
    /// "the run I already triaged" from "a new run that re-stamped the badge".
    public static func latestEvent(in thread: ChatThread) -> ThreadEvent? {
        store.latestEvent(in: thread)
    }

    /// The stable id of the most recent integrity-record event, or nil if none. This is the identity a
    /// triage decision binds to, so a NEW run (new id) re-opens triage even if the verdict is the same.
    public static func latestRecordID(in thread: ChatThread) -> UUID? {
        latestEvent(in: thread)?.id
    }

    /// Scans the thread, then records the resulting verdict as a fresh notice event.
    @discardableResult
    public static func record(into thread: inout ChatThread) -> RunIntegrityReport {
        let report = RunIntegrityScanner.scan(thread)
        store.upsert(Payload(verdict: report.verdict, summary: report.summaryLine), into: &thread)
        return report
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        store.isRecord(event)
    }
}
