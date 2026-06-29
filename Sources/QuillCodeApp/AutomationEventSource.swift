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

/// Fires when a watched file appears or is modified after the last check. This
/// is the first concrete `AutomationEventSource`; wiring it into the automation
/// engine's monitor tick is a follow-up tracked in ROADMAP.md.
public struct FileChangeEventSource: AutomationEventSource {
    public var path: URL
    private let fileManager: FileManager

    public init(path: URL, fileManager: FileManager = .default) {
        self.path = path
        self.fileManager = fileManager
    }

    public func pendingEvent(since: Date?) -> String? {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: path.path),
            let modified = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        if let since, modified <= since {
            return nil
        }
        return "\(path.lastPathComponent) changed"
    }
}
