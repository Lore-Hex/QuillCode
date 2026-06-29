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

/// Fires when a watched file appears or is modified after the last check. This
/// is the first concrete `AutomationEventSource`; wiring it into the automation
/// engine's monitor tick is a follow-up tracked in ROADMAP.md.
public struct FileChangeEventSource: AutomationEventSource {
    public var path: URL
    private let modificationDate: FileModificationDateProvider

    public init(
        path: URL,
        modificationDate: @escaping FileModificationDateProvider = Self.defaultModificationDate
    ) {
        self.path = path
        self.modificationDate = modificationDate
    }

    public func pendingEvent(since: Date?) -> String? {
        guard let modified = modificationDate(path) else {
            return nil
        }
        if let since, modified <= since {
            return nil
        }
        return "\(path.lastPathComponent) changed"
    }

    @usableFromInline
    static func defaultModificationDate(for path: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path.path)
        return attributes?[.modificationDate] as? Date
    }
}
