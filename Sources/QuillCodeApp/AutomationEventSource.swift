import Foundation
import QuillCodeCore

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

/// Fires when a watched file appears or is modified after the last check.
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

enum AutomationEventSourceResolver {
    static func eventSource(
        for definition: QuillAutomationEventSource,
        project: ProjectRef?
    ) -> (any AutomationEventSource)? {
        switch definition.kind {
        case .fileChange:
            guard let url = fileChangeURL(for: definition.path, project: project) else {
                return nil
            }
            return FileChangeEventSource(path: url)
        }
    }

    static func fileChangeURL(for path: String, project: ProjectRef?) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }

        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed).standardizedFileURL
        }

        guard let project, !project.isRemote else { return nil }
        let root = URL(fileURLWithPath: project.path).standardizedFileURL
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        guard isContained(candidate, inside: root) else { return nil }
        return candidate
    }

    private static func isContained(_ candidate: URL, inside root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        if candidatePath == rootPath {
            return true
        }
        let prefix = rootPath.hasSuffix("/") ? rootPath : "\(rootPath)/"
        return candidatePath.hasPrefix(prefix)
    }
}
