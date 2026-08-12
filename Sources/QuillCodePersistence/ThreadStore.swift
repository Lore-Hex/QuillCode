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
    public var deferredThreadCount: Int
    public var summaryCacheHitCount: Int

    public init(
        threads: [ChatThread],
        unreadable: [URL],
        directoryReadFailed: Bool = false,
        deferredThreadCount: Int = 0,
        summaryCacheHitCount: Int = 0
    ) {
        self.threads = threads
        self.unreadable = unreadable
        self.issues = unreadable.map {
            ThreadFileIssue(fileURL: $0, reason: .unreadable)
        }
        self.directoryReadFailed = directoryReadFailed
        self.deferredThreadCount = deferredThreadCount
        self.summaryCacheHitCount = summaryCacheHitCount
    }

    public init(
        threads: [ChatThread],
        issues: [ThreadFileIssue],
        directoryReadFailed: Bool = false,
        deferredThreadCount: Int = 0,
        summaryCacheHitCount: Int = 0
    ) {
        self.threads = threads
        self.unreadable = issues.map(\.fileURL)
        self.issues = issues
        self.directoryReadFailed = directoryReadFailed
        self.deferredThreadCount = deferredThreadCount
        self.summaryCacheHitCount = summaryCacheHitCount
    }
}

public enum JSONThreadStoreError: LocalizedError, Equatable, Sendable {
    case notRegularFile
    case symbolicLink
    case exceedsSizeLimit(maximumBytes: Int)
    case deferredPayloadMutation

    public var errorDescription: String? {
        switch self {
        case .notRegularFile:
            "The saved chat path is not a regular file."
        case .symbolicLink:
            "The saved chat path is a symbolic link."
        case .exceedsSizeLimit(let maximumBytes):
            "The saved chat exceeds the \(maximumBytes)-byte loading limit."
        case .deferredPayloadMutation:
            "The archived chat must be loaded before changing transcript content."
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
        let thread = try materialize(thread)
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
        if thread.isArchived {
            // The summary index contains bounded transcript excerpts. Any archived rewrite may have
            // cleared or replaced that content, so discard all derived entries instead of retaining
            // stale text until the next bootstrap fingerprint pass.
            ArchivedThreadSummaryIndexStore.remove(from: directory)
        }
    }

    public func load(_ id: UUID) throws -> ChatThread {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Self.boundedData(contentsOf: fileURL(for: id))
        return ThreadEventLogCompactor.compact(try decoder.decode(ChatThread.self, from: data))
    }

    public func delete(_ id: UUID) throws {
        let url = fileURL(for: id)
        ArchivedThreadSummaryIndexStore.remove(from: directory)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func contains(_ id: UUID) -> Bool {
        guard let values = try? fileURL(for: id).resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    public func list() throws -> [ChatThread] {
        listing().threads
    }

    /// Startup-oriented listing that keeps old archived transcript payloads on disk. The summary
    /// index is validated against each authoritative file's size and modification date; a miss or
    /// damaged index falls back to the normal bounded decode for that one file.
    public func bootstrapListing(deferArchivedBefore cutoff: Date) -> ThreadListing {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ThreadListing(threads: [], issues: [])
        }
        guard let urls = threadFileURLs() else {
            return ThreadListing(threads: [], issues: [], directoryReadFailed: true)
        }

        let cachedIndex = ArchivedThreadSummaryIndexStore.load(from: directory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var threads: [ChatThread] = []
        var issues: [ThreadFileIssue] = []
        var nextEntries: [String: ArchivedThreadSummaryIndex.Entry] = [:]
        var deferredThreadCount = 0
        var summaryCacheHitCount = 0

        for url in urls {
            let fingerprint = ThreadFileFingerprint.read(from: url)
            let cachedEntry: ArchivedThreadSummaryIndex.Entry?
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
               let entry = cachedIndex?.entries[id.uuidString],
               let fingerprint,
               entry.matches(fileURL: url, fingerprint: fingerprint) {
                cachedEntry = entry
            } else {
                cachedEntry = nil
            }
            if let cachedEntry, cachedEntry.updatedAt < cutoff {
                threads.append(cachedEntry.deferredThread())
                nextEntries[cachedEntry.id.uuidString] = cachedEntry
                deferredThreadCount += 1
                summaryCacheHitCount += 1
                continue
            }

            do {
                let data = try Self.boundedData(contentsOf: url)
                let decoded = try decoder.decode(ChatThread.self, from: data)
                let compacted = ThreadEventLogCompactor.compact(decoded)
                var currentFingerprint = fingerprint
                if compacted.events.count != decoded.events.count {
                    if (try? save(compacted)) != nil {
                        currentFingerprint = ThreadFileFingerprint.read(from: url)
                    }
                }

                if let currentFingerprint,
                   let entry = ArchivedThreadSummaryIndex.Entry(
                       thread: compacted,
                       fileURL: url,
                       fingerprint: currentFingerprint
                   ),
                   entry.updatedAt < cutoff {
                    nextEntries[entry.id.uuidString] = entry
                    threads.append(entry.deferredThread())
                    deferredThreadCount += 1
                    continue
                }
                threads.append(compacted)
            } catch let error as JSONThreadStoreError {
                issues.append(ThreadFileIssue(fileURL: url, reason: Self.issueReason(for: error)))
            } catch {
                issues.append(ThreadFileIssue(fileURL: url, reason: .unreadable))
            }
        }

        threads.sort { $0.updatedAt > $1.updatedAt }
        let boundedEntries = ArchivedThreadSummaryIndexStore.bounded(nextEntries)
        if cachedIndex?.entries != boundedEntries {
            ArchivedThreadSummaryIndexStore.save(entries: boundedEntries, to: directory)
        }
        return ThreadListing(
            threads: threads,
            issues: issues,
            deferredThreadCount: deferredThreadCount,
            summaryCacheHitCount: summaryCacheHitCount
        )
    }

    /// Best-effort listing that self-heals around damage: a single truncated (crash-mid-write),
    /// hand-edited, or schema-skewed thread file must NOT empty the entire sidebar — every healthy
    /// conversation still loads and the unreadable files are reported separately. `load(_:)` stays
    /// strict, so a direct open of a named corrupt thread still surfaces the decode error.
    public func listing() -> ThreadListing {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ThreadListing(threads: [], issues: [])
        }
        guard let urls = threadFileURLs() else {
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
        case .deferredPayloadMutation:
            .unreadable
        }
    }

    public func materialize(_ thread: ChatThread) throws -> ChatThread {
        guard !thread.payloadResidency.isLoaded else { return thread }
        return try DeferredThreadPayloadMerger.merge(summary: thread, into: load(thread.id))
    }

    private func threadFileURLs() -> [URL]? {
        try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        ).filter({ $0.pathExtension == "json" }).sorted(by: {
            $0.lastPathComponent < $1.lastPathComponent
        })
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }
}
