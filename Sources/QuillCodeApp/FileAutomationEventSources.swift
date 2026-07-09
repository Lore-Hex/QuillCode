import Foundation

/// Fires when a watched file appears or is modified after the last check.
public struct FileChangeEventSource: AutomationEventSource {
    public var path: URL
    private let modificationDate: FileModificationDateProvider

    public init(
        path: URL,
        modificationDate: @escaping FileModificationDateProvider = FileModificationDateReader.modificationDate
    ) {
        self.path = path
        self.modificationDate = modificationDate
    }

    public func pendingEvent(since: Date?) -> String? {
        guard let modified = modificationDate(path),
              since.map({ modified > $0 }) ?? true
        else {
            return nil
        }
        return "\(path.lastPathComponent) changed"
    }
}

/// Fires when a watched directory's metadata changes after the last check.
public struct DirectoryChangeEventSource: AutomationEventSource {
    public var path: URL
    private let modificationDate: FileModificationDateProvider

    public init(
        path: URL,
        modificationDate: @escaping FileModificationDateProvider = FileModificationDateReader.modificationDate
    ) {
        self.path = path
        self.modificationDate = modificationDate
    }

    public func pendingEvent(since: Date?) -> String? {
        guard let modified = modificationDate(path),
              since.map({ modified > $0 }) ?? true
        else {
            return nil
        }
        return "\(path.lastPathComponent) directory changed"
    }
}

@usableFromInline
enum FileModificationDateReader {
    @usableFromInline
    static func modificationDate(for path: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path.path)
        return attributes?[.modificationDate] as? Date
    }
}
