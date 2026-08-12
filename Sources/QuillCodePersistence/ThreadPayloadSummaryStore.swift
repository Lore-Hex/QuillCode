import Foundation
import QuillCodeCore

/// A compact, fingerprint-bound projection of one persisted chat. Entries are stored separately so
/// an authoritative thread write invalidates only its own derived cache instead of rewriting a
/// workspace-wide index during streaming updates.
struct ThreadPayloadSummaryEntry: Codable, Hashable {
    static let schemaVersion = 2
    static let maximumAttachmentIDs = 10_000

    var schemaVersion: Int
    var fingerprint: ThreadFileFingerprint
    var id: UUID
    var title: String
    var projectID: UUID?
    var mode: AgentMode
    var model: String
    var personality: QuillCodePersonality
    var goal: ThreadGoal?
    var isPinned: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    var worktree: WorktreeBinding?
    var pullRequest: PullRequestLink?
    var forkParentThreadID: UUID?
    var forkAnchorTurnMessageID: UUID?
    var subagentRuns: [SubagentRunRecord]
    var searchText: String
    var attachmentIDs: [UUID]
    var agentImportProvenance: AgentImportThreadProvenance?
    var attentionItem: AttentionItem?
    var periodUsage: ThreadPeriodUsageSnapshot

    init?(
        thread: ChatThread,
        fileURL: URL,
        fingerprint: ThreadFileFingerprint,
        retainingUsageSince usageRetentionStart: Date,
        calendar: Calendar,
        now: Date
    ) {
        let loadedAttachmentIDs = Set(
            (
                thread.composerAttachments
                    + thread.followUpQueue.flatMap(\.attachments)
                    + thread.messages.flatMap(\.attachments)
            ).map(\.id)
        )
        let attachmentIDs = thread.payloadResidency.deferredSummary?.attachmentIDs
            ?? loadedAttachmentIDs
        guard attachmentIDs.count <= Self.maximumAttachmentIDs,
              fileURL.lastPathComponent == "\(thread.id.uuidString).json",
              let periodUsage = ThreadPeriodUsageSnapshot(
                  thread: thread,
                  retainingSince: usageRetentionStart,
                  calendar: calendar,
                  now: now
              )
        else {
            return nil
        }

        self.schemaVersion = Self.schemaVersion
        self.fingerprint = fingerprint
        self.id = thread.id
        self.title = thread.title
        self.projectID = thread.projectID
        self.mode = thread.mode
        self.model = thread.model
        self.personality = thread.personality
        self.goal = thread.goal
        self.isPinned = thread.isPinned
        self.isArchived = thread.isArchived
        self.createdAt = thread.createdAt
        self.updatedAt = thread.updatedAt
        self.worktree = thread.worktree
        self.pullRequest = thread.pullRequest
        self.forkParentThreadID = thread.forkParentThreadID
        self.forkAnchorTurnMessageID = thread.forkAnchorTurnMessageID
        self.subagentRuns = thread.subagentRuns
        self.searchText = thread.payloadResidency.deferredSearchText
            ?? ThreadSearchTextBuilder.build(from: thread.messages)
        self.attachmentIDs = attachmentIDs.sorted { $0.uuidString < $1.uuidString }
        self.agentImportProvenance = AgentImportThreadProvenance.value(in: thread)
        self.attentionItem = AttentionModel.build(from: [thread]).items.first
        self.periodUsage = periodUsage
    }

    func matches(
        fileURL: URL,
        fingerprint currentFingerprint: ThreadFileFingerprint,
        calendar: Calendar
    ) -> Bool {
        schemaVersion == Self.schemaVersion
            && fileURL.lastPathComponent == "\(id.uuidString).json"
            && fingerprint == currentFingerprint
            && searchText.count <= ThreadSearchTextBuilder.maximumCharacters
            && attachmentIDs.count <= Self.maximumAttachmentIDs
            && periodUsage.isCompatible(with: calendar)
            && periodUsage.events.allSatisfy { ModelTokenUsageEvent.record(from: $0) != nil }
    }

    func deferredThread() -> ChatThread {
        ChatThread(
            id: id,
            title: title,
            projectID: projectID,
            mode: mode,
            model: model,
            personality: personality,
            subagentRuns: subagentRuns,
            goal: goal,
            isPinned: isPinned,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt,
            worktree: worktree,
            pullRequest: pullRequest,
            forkParentThreadID: forkParentThreadID,
            forkAnchorTurnMessageID: forkAnchorTurnMessageID,
            payloadResidency: .deferred(DeferredThreadPayloadSummary(
                searchText: searchText,
                attachmentIDs: Set(attachmentIDs),
                agentImportProvenance: agentImportProvenance,
                attentionItem: attentionItem,
                periodUsage: periodUsage
            ))
        )
    }
}

struct ThreadFileFingerprint: Codable, Hashable {
    var size: Int
    var modificationDate: Date

    static func read(from fileURL: URL) -> ThreadFileFingerprint? {
        guard let values = try? fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]),
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        let size = values.fileSize,
        size >= 0,
        let modificationDate = values.contentModificationDate
        else {
            return nil
        }
        return ThreadFileFingerprint(size: size, modificationDate: modificationDate)
    }
}

enum ThreadPayloadSummaryStore {
    static let maximumEntryBytes = 2 * 1_024 * 1_024
    private static let directoryName = ".thread-payload-summaries-v2"
    private static let legacyIndexName = ".archived-thread-summary-index-v1"

    static func load(
        threadID: UUID,
        authoritativeFileURL: URL,
        fingerprint: ThreadFileFingerprint,
        calendar: Calendar,
        from threadDirectory: URL
    ) -> ThreadPayloadSummaryEntry? {
        let directory = cacheDirectory(in: threadDirectory)
        let filename = cacheFilename(for: threadID)
        do {
            guard let data = try PrivateFileStoreFileSystem.read(
                directory: directory,
                filename: filename,
                maximumBytes: maximumEntryBytes
            ) else {
                return nil
            }
            let entry = try JSONDecoder().decode(ThreadPayloadSummaryEntry.self, from: data)
            guard entry.id == threadID,
                  entry.matches(
                      fileURL: authoritativeFileURL,
                      fingerprint: fingerprint,
                      calendar: calendar
                  )
            else {
                remove(threadID: threadID, from: threadDirectory)
                return nil
            }
            return entry
        } catch {
            remove(threadID: threadID, from: threadDirectory)
            return nil
        }
    }

    static func save(_ entry: ThreadPayloadSummaryEntry, to threadDirectory: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entry), data.count <= maximumEntryBytes else { return }
        try? PrivateFileStoreFileSystem.write(
            data,
            directory: cacheDirectory(in: threadDirectory),
            filename: cacheFilename(for: entry.id)
        )
    }

    static func remove(threadID: UUID, from threadDirectory: URL) {
        try? PrivateFileStoreFileSystem.delete(
            directory: cacheDirectory(in: threadDirectory),
            filename: cacheFilename(for: threadID)
        )
    }

    static func removeLegacyIndex(from threadDirectory: URL) {
        try? FileManager.default.removeItem(
            at: threadDirectory.appendingPathComponent(legacyIndexName, isDirectory: false)
        )
    }

    static func cacheFileURL(for threadID: UUID, in threadDirectory: URL) -> URL {
        cacheDirectory(in: threadDirectory)
            .appendingPathComponent(cacheFilename(for: threadID), isDirectory: false)
    }

    private static func cacheDirectory(in threadDirectory: URL) -> URL {
        threadDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static func cacheFilename(for threadID: UUID) -> String {
        "\(threadID.uuidString).json"
    }
}

enum DeferredThreadPayloadMerger {
    static func merge(summary: ChatThread, into persisted: ChatThread) throws -> ChatThread {
        guard !summary.payloadResidency.isLoaded else { return summary }
        guard summary.id == persisted.id,
              summary.instructions.isEmpty,
              summary.memories.isEmpty,
              summary.messages.isEmpty,
              summary.modelContextItems.isEmpty,
              summary.events.isEmpty,
              summary.composerDraft == nil,
              summary.composerAttachments.isEmpty,
              summary.followUpQueue.isEmpty
        else {
            throw JSONThreadStoreError.deferredPayloadMutation
        }

        var merged = persisted
        merged.title = summary.title
        merged.projectID = summary.projectID
        merged.mode = summary.mode
        merged.model = summary.model
        merged.personality = summary.personality
        merged.subagentRuns = summary.subagentRuns
        merged.goal = summary.goal
        merged.isPinned = summary.isPinned
        merged.isArchived = summary.isArchived
        merged.createdAt = summary.createdAt
        merged.updatedAt = summary.updatedAt
        merged.worktree = summary.worktree
        merged.pullRequest = summary.pullRequest
        merged.forkParentThreadID = summary.forkParentThreadID
        merged.forkAnchorTurnMessageID = summary.forkAnchorTurnMessageID
        merged.payloadResidency = .loaded
        return merged
    }
}
