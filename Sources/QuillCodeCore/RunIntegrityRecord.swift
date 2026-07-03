import Foundation

/// Persists a `RunIntegrityReport` onto a thread as a `.notice` event so the badge is stable across
/// reloads. Reuses the notice-event convention already used for other post-hoc annotations.
public enum RunIntegrityRecord {
    /// The well-known summary marker that identifies the integrity notice among a thread's events.
    public static let eventSummary = "run-integrity-report"

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
        let payload = Payload(verdict: report.verdict, summary: report.summaryLine)
        guard let payloadJSON = try? JSONHelpers.encodePretty(payload) else { return nil }
        return ThreadEvent(kind: .notice, summary: eventSummary, payloadJSON: payloadJSON)
    }

    /// The most recently recorded integrity verdict on a thread, or nil if none was ever recorded.
    public static func latest(in thread: ChatThread) -> Payload? {
        for event in thread.events.reversed() where isRecord(event) {
            if let payloadJSON = event.payloadJSON,
               let payload = try? JSONHelpers.decode(Payload.self, from: payloadJSON) {
                return payload
            }
        }
        return nil
    }

    /// Scans the thread, then records the resulting verdict as a fresh notice event.
    @discardableResult
    public static func record(into thread: inout ChatThread) -> RunIntegrityReport {
        let report = RunIntegrityScanner.scan(thread)
        thread.events.removeAll(where: isRecord)
        if let event = event(for: report) {
            thread.events.append(event)
            thread.updatedAt = Date()
        }
        return report
    }

    public static func isRecord(_ event: ThreadEvent) -> Bool {
        event.kind == .notice && event.summary == eventSummary
    }
}
