import Foundation

/// A source of external events a `monitor` automation can watch, so a monitor
/// can fire when something actually changes instead of only on a schedule.
///
/// Adapters are deterministic and side-effect free for a given `since`, so the
/// automation engine can poll them on its tick and compare against the
/// automation's `lastRunAt` to decide whether to fire.
public protocol AutomationEventSource: Sendable {
    /// Returns a short human-readable description of the event when one has
    /// occurred after `since` (or ever, when `since` is `nil`), otherwise `nil`.
    func pendingEvent(since: Date?) -> String?
}

public typealias FileModificationDateProvider = @Sendable (URL) -> Date?
public typealias URLLastModifiedDateProvider = @Sendable (URL) -> Date?
public typealias URLFeedLatestDateProvider = @Sendable (URL) -> Date?
