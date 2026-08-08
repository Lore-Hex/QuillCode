import Foundation
import QuillCodeCore

public enum ThreadFileIssueReason: String, Sendable, Hashable {
    case unreadable
    case notRegularFile = "not-regular-file"
    case symbolicLink = "symbolic-link"
    case exceedsSizeLimit = "exceeds-size-limit"
}

public struct ThreadFileIssue: Sendable, Hashable {
    public var fileURL: URL
    public var reason: ThreadFileIssueReason

    public init(fileURL: URL, reason: ThreadFileIssueReason) {
        self.fileURL = fileURL
        self.reason = reason
    }
}

/// Result of a best-effort thread listing: the healthy threads that decoded plus bounded,
/// content-free diagnostics for files that were rejected. Callers can keep healthy chats visible
/// and offer recovery guidance without loading hostile files or exposing their contents.
public struct ThreadListing: Sendable {
    public var threads: [ChatThread]
    public var unreadable: [URL]
    public var issues: [ThreadFileIssue]
    public var directoryReadFailed: Bool

    public init(
        threads: [ChatThread],
        unreadable: [URL],
        directoryReadFailed: Bool = false
    ) {
        self.threads = threads
        self.unreadable = unreadable
        self.issues = unreadable.map {
            ThreadFileIssue(fileURL: $0, reason: .unreadable)
        }
        self.directoryReadFailed = directoryReadFailed
    }

    public init(
        threads: [ChatThread],
        issues: [ThreadFileIssue],
        directoryReadFailed: Bool = false
    ) {
        self.threads = threads
        self.unreadable = issues.map(\.fileURL)
        self.issues = issues
        self.directoryReadFailed = directoryReadFailed
    }
}

public enum JSONThreadStoreError: LocalizedError, Equatable, Sendable {
    case notRegularFile
    case symbolicLink
    case exceedsSizeLimit(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .notRegularFile:
            "The saved chat path is not a regular file."
        case .symbolicLink:
            "The saved chat path is a symbolic link."
        case .exceedsSizeLimit(let maximumBytes):
            "The saved chat exceeds the \(maximumBytes)-byte loading limit."
        }
    }
}

public struct JSONThreadStore: Sendable {
    public static let maximumThreadFileBytes = 128 * 1_024 * 1_024

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ thread: ChatThread) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ThreadEventLogCompactor.compact(thread))
        guard data.count <= Self.maximumThreadFileBytes else {
            throw JSONThreadStoreError.exceedsSizeLimit(
                maximumBytes: Self.maximumThreadFileBytes
            )
        }
        try data.write(to: fileURL(for: thread.id), options: .atomic)
    }

    public func load(_ id: UUID) throws -> ChatThread {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Self.boundedData(contentsOf: fileURL(for: id))
        return ThreadEventLogCompactor.compact(try decoder.decode(ChatThread.self, from: data))
    }

    public func delete(_ id: UUID) throws {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func list() throws -> [ChatThread] {
        listing().threads
    }

    /// Best-effort listing that self-heals around damage: a single truncated (crash-mid-write),
    /// hand-edited, or schema-skewed thread file must NOT empty the entire sidebar — every healthy
    /// conversation still loads and the unreadable files are reported separately. `load(_:)` stays
    /// strict, so a direct open of a named corrupt thread still surfaces the decode error.
    public func listing() -> ThreadListing {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ThreadListing(threads: [], issues: [])
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ).filter({ $0.pathExtension == "json" }).sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        }) else {
            return ThreadListing(threads: [], issues: [], directoryReadFailed: true)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var threads: [ChatThread] = []
        var issues: [ThreadFileIssue] = []
        for url in urls {
            do {
                let data = try Self.boundedData(contentsOf: url)
                let decoded = try decoder.decode(ChatThread.self, from: data)
                let compacted = ThreadEventLogCompactor.compact(decoded)
                threads.append(compacted)
                if compacted.events.count != decoded.events.count {
                    try? save(compacted)
                }
            } catch let error as JSONThreadStoreError {
                issues.append(ThreadFileIssue(fileURL: url, reason: Self.issueReason(for: error)))
            } catch {
                issues.append(ThreadFileIssue(fileURL: url, reason: .unreadable))
            }
        }
        threads.sort { $0.updatedAt > $1.updatedAt }
        return ThreadListing(threads: threads, issues: issues)
    }

    private static func boundedData(contentsOf url: URL) throws -> Data {
        do {
            return try BoundedFileDataReader.read(
                from: url,
                maximumBytes: maximumThreadFileBytes
            )
        } catch let error as BoundedFileDataError {
            switch error {
            case .invalidSizeLimit:
                throw JSONThreadStoreError.exceedsSizeLimit(
                    maximumBytes: maximumThreadFileBytes
                )
            case .notRegularFile:
                throw JSONThreadStoreError.notRegularFile
            case .symbolicLink:
                throw JSONThreadStoreError.symbolicLink
            case .exceedsSizeLimit:
                throw JSONThreadStoreError.exceedsSizeLimit(
                    maximumBytes: maximumThreadFileBytes
                )
            }
        }
    }

    private static func issueReason(for error: JSONThreadStoreError) -> ThreadFileIssueReason {
        switch error {
        case .notRegularFile:
            .notRegularFile
        case .symbolicLink:
            .symbolicLink
        case .exceedsSizeLimit:
            .exceedsSizeLimit
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
