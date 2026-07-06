import Foundation
import QuillCodeCore

/// Result of a best-effort thread listing: the healthy threads that decoded, plus the file URLs
/// that could not be read (truncated, hand-edited, or schema-skewed) so callers can surface a
/// self-healing notice instead of silently losing data.
public struct ThreadListing: Sendable {
    public var threads: [ChatThread]
    public var unreadable: [URL]

    public init(threads: [ChatThread], unreadable: [URL]) {
        self.threads = threads
        self.unreadable = unreadable
    }
}

public struct JSONThreadStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ thread: ChatThread) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(thread)
        try data.write(to: fileURL(for: thread.id), options: .atomic)
    }

    public func load(_ id: UUID) throws -> ChatThread {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: fileURL(for: id))
        return try decoder.decode(ChatThread.self, from: data)
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
            return ThreadListing(threads: [], unreadable: [])
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" }) else {
            return ThreadListing(threads: [], unreadable: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var threads: [ChatThread] = []
        var unreadable: [URL] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let thread = try? decoder.decode(ChatThread.self, from: data) else {
                unreadable.append(url)
                continue
            }
            threads.append(thread)
        }
        threads.sort { $0.updatedAt > $1.updatedAt }
        return ThreadListing(threads: threads, unreadable: unreadable)
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
