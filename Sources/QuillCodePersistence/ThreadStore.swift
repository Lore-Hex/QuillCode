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
            "The chat must be loaded before changing transcript content."
        }
    }
}

public struct JSONThreadStore: Sendable {
    public static let maximumThreadFileBytes = 128 * 1_024 * 1_024
    public static let defaultMaximumResidentActivePayloads = 12

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
        // A summary contains derived transcript excerpts. Invalidate this thread's cache immediately
        // after any authoritative rewrite so clear/edit operations never leave stale private text.
        ThreadPayloadSummaryStore.remove(threadID: thread.id, from: directory)
    }

    public func load(_ id: UUID) throws -> ChatThread {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Self.boundedData(contentsOf: fileURL(for: id))
        return ThreadEventLogCompactor.compact(try decoder.decode(ChatThread.self, from: data))
    }

    public func delete(_ id: UUID) throws {
        let url = fileURL(for: id)
        ThreadPayloadSummaryStore.remove(threadID: id, from: directory)
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

    /// Startup-oriented listing that keeps archived and cold active transcript payloads on disk.
    /// Per-thread summaries are fingerprint-validated; a miss falls back to one bounded decode.
    public func bootstrapListing(
        deferArchivedBefore cutoff: Date,
        maximumResidentActivePayloads: Int = .max,
        retainingUsageSince usageRetentionStart: Date = .distantFuture,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ThreadListing {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return ThreadListing(threads: [], issues: [])
        }
        guard let urls = threadFileURLs() else {
            return ThreadListing(threads: [], issues: [], directoryReadFailed: true)
        }

        ThreadPayloadSummaryStore.removeLegacyIndex(from: directory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var threads: [ChatThread] = []
        var issues: [ThreadFileIssue] = []
        var cacheHitThreadIDs = Set<UUID>()
        let defersActivePayloads = maximumResidentActivePayloads != .max

        for url in urls {
            let fingerprint = ThreadFileFingerprint.read(from: url)
            let threadID = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            let cachedEntry = threadID.flatMap { id in
                fingerprint.flatMap { fingerprint in
                    ThreadPayloadSummaryStore.load(
                        threadID: id,
                        authoritativeFileURL: url,
                        fingerprint: fingerprint,
                        calendar: calendar,
                        from: directory
                    )
                }
            }
            if let cachedEntry,
               Self.shouldInitiallyDefer(
                   isArchived: cachedEntry.isArchived,
                   updatedAt: cachedEntry.updatedAt,
                   archiveCutoff: cutoff,
                   defersActivePayloads: defersActivePayloads
               ) {
                threads.append(cachedEntry.deferredThread())
                cacheHitThreadIDs.insert(cachedEntry.id)
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
                   Self.shouldInitiallyDefer(
                       isArchived: compacted.isArchived,
                       updatedAt: compacted.updatedAt,
                       archiveCutoff: cutoff,
                       defersActivePayloads: defersActivePayloads
                   ),
                   let entry = ThreadPayloadSummaryEntry(
                       thread: compacted,
                       fileURL: url,
                       fingerprint: currentFingerprint,
                       retainingUsageSince: usageRetentionStart,
                       calendar: calendar,
                       now: now
                   ) {
                    ThreadPayloadSummaryStore.save(entry, to: directory)
                    threads.append(entry.deferredThread())
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
        if defersActivePayloads {
            Self.hydrateResidentActivePayloads(
                in: &threads,
                store: self,
                maximumCount: max(0, maximumResidentActivePayloads)
            )
        }
        let deferredThreadIDs = Set(
            threads.lazy.filter { !$0.payloadResidency.isLoaded }.map(\.id)
        )
        return ThreadListing(
            threads: threads,
            issues: issues,
            deferredThreadCount: deferredThreadIDs.count,
            summaryCacheHitCount: cacheHitThreadIDs.intersection(deferredThreadIDs).count
        )
    }

    private static func shouldInitiallyDefer(
        isArchived: Bool,
        updatedAt: Date,
        archiveCutoff: Date,
        defersActivePayloads: Bool
    ) -> Bool {
        isArchived ? updatedAt < archiveCutoff : defersActivePayloads
    }

    private static func hydrateResidentActivePayloads(
        in threads: inout [ChatThread],
        store: JSONThreadStore,
        maximumCount: Int
    ) {
        let loadedCount = threads.lazy.filter {
            !$0.isArchived && $0.payloadResidency.isLoaded
        }.count
        let availableSlots = max(0, maximumCount - loadedCount)
        let deferredActiveIDs = threads.lazy
            .filter { !$0.isArchived && !$0.payloadResidency.isLoaded }
            .map(\.id)
        var residentIDs = Set(deferredActiveIDs.prefix(availableSlots))
        if let selectedID = threads.first(where: { !$0.isArchived })?.id {
            residentIDs.insert(selectedID)
        }

        for index in threads.indices where residentIDs.contains(threads[index].id) {
            if let hydrated = try? store.materialize(threads[index]) {
                threads[index] = hydrated
            }
        }
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

    /// Releases a durable in-memory transcript into the same bounded summary used at startup.
    /// The caller owns dirty-state and active-run checks; a missing or unsafe authoritative file
    /// leaves the payload resident.
    public func deferPayload(
        _ thread: ChatThread,
        retainingUsageSince usageRetentionStart: Date,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> ChatThread? {
        guard thread.payloadResidency.isLoaded,
              let fingerprint = ThreadFileFingerprint.read(from: fileURL(for: thread.id)),
              let entry = ThreadPayloadSummaryEntry(
                  thread: thread,
                  fileURL: fileURL(for: thread.id),
                  fingerprint: fingerprint,
                  retainingUsageSince: usageRetentionStart,
                  calendar: calendar,
                  now: now
              )
        else {
            return nil
        }
        ThreadPayloadSummaryStore.save(entry, to: directory)
        return entry.deferredThread()
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
