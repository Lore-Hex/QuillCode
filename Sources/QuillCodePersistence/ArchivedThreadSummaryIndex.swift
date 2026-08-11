import Foundation
import QuillCodeCore

struct ArchivedThreadSummaryIndex: Codable, Hashable {
    static let schemaVersion = 1
    static let maximumBytes = 64 * 1_024 * 1_024
    static let maximumEntries = 5_000
    static let maximumAttachmentIDsPerThread = 10_000

    var schemaVersion: Int
    var entries: [String: Entry]

    struct Entry: Codable, Hashable {
        var fingerprint: ThreadFileFingerprint
        var id: UUID
        var title: String
        var projectID: UUID?
        var mode: AgentMode
        var model: String
        var personality: QuillCodePersonality
        var goal: ThreadGoal?
        var isPinned: Bool
        var createdAt: Date
        var updatedAt: Date
        var worktree: WorktreeBinding?
        var pullRequest: PullRequestLink?
        var forkParentThreadID: UUID?
        var forkAnchorTurnMessageID: UUID?
        var searchText: String
        var attachmentIDs: [UUID]
        var agentImportProvenance: AgentImportThreadProvenance?
        var attentionItem: AttentionItem?

        init?(thread: ChatThread, fileURL: URL, fingerprint: ThreadFileFingerprint) {
            let loadedAttachmentIDs = Set(
                (
                    thread.composerAttachments
                        + thread.followUpQueue.flatMap(\.attachments)
                        + thread.messages.flatMap(\.attachments)
                ).map(\.id)
            )
            let attachmentIDs = thread.payloadResidency.deferredSummary?.attachmentIDs
                ?? loadedAttachmentIDs
            guard thread.isArchived,
                  thread.subagentRuns.isEmpty,
                  attachmentIDs.count <= ArchivedThreadSummaryIndex.maximumAttachmentIDsPerThread,
                  fileURL.lastPathComponent == "\(thread.id.uuidString).json"
            else { return nil }

            self.fingerprint = fingerprint
            self.id = thread.id
            self.title = thread.title
            self.projectID = thread.projectID
            self.mode = thread.mode
            self.model = thread.model
            self.personality = thread.personality
            self.goal = thread.goal
            self.isPinned = thread.isPinned
            self.createdAt = thread.createdAt
            self.updatedAt = thread.updatedAt
            self.worktree = thread.worktree
            self.pullRequest = thread.pullRequest
            self.forkParentThreadID = thread.forkParentThreadID
            self.forkAnchorTurnMessageID = thread.forkAnchorTurnMessageID
            self.searchText = thread.payloadResidency.deferredSearchText
                ?? ThreadSearchTextBuilder.build(from: thread.messages)
            self.attachmentIDs = attachmentIDs.sorted { $0.uuidString < $1.uuidString }
            self.agentImportProvenance = AgentImportThreadProvenance.value(in: thread)
            self.attentionItem = AttentionModel.build(from: [thread]).items.first
        }

        func matches(fileURL: URL, fingerprint currentFingerprint: ThreadFileFingerprint) -> Bool {
            fileURL.lastPathComponent == "\(id.uuidString).json"
                && fingerprint == currentFingerprint
                && searchText.count <= ThreadSearchTextBuilder.maximumCharacters
        }

        func deferredThread() -> ChatThread {
            ChatThread(
                id: id,
                title: title,
                projectID: projectID,
                mode: mode,
                model: model,
                personality: personality,
                goal: goal,
                isPinned: isPinned,
                isArchived: true,
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
                    attentionItem: attentionItem
                ))
            )
        }
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
        else { return nil }

        return ThreadFileFingerprint(size: size, modificationDate: modificationDate)
    }
}

enum ArchivedThreadSummaryIndexStore {
    private static let fileName = ".archived-thread-summary-index-v1"

    static func load(from directory: URL) -> ArchivedThreadSummaryIndex? {
        let fileURL = indexURL(in: directory)
        let data: Data
        do {
            guard let loaded = try BoundedFileDataReader.readIfPresent(
                from: fileURL,
                maximumBytes: ArchivedThreadSummaryIndex.maximumBytes
            ) else { return nil }
            data = loaded
        } catch {
            return nil
        }
        guard let index = try? JSONDecoder().decode(ArchivedThreadSummaryIndex.self, from: data),
        index.schemaVersion == ArchivedThreadSummaryIndex.schemaVersion,
        index.entries.count <= ArchivedThreadSummaryIndex.maximumEntries,
        index.entries.allSatisfy({ key, entry in
            key == entry.id.uuidString
                && entry.searchText.count <= ThreadSearchTextBuilder.maximumCharacters
                && entry.attachmentIDs.count
                    <= ArchivedThreadSummaryIndex.maximumAttachmentIDsPerThread
        })
        else { return nil }
        return index
    }

    static func save(
        entries: [String: ArchivedThreadSummaryIndex.Entry],
        to directory: URL
    ) {
        let fileURL = indexURL(in: directory)
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let boundedEntries = bounded(entries)
        let index = ArchivedThreadSummaryIndex(
            schemaVersion: ArchivedThreadSummaryIndex.schemaVersion,
            entries: boundedEntries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(index),
              data.count <= ArchivedThreadSummaryIndex.maximumBytes
        else { return }

        do {
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // This index is a disposable optimization. Authoritative chat files remain untouched.
        }
    }

    static func remove(from directory: URL) {
        try? FileManager.default.removeItem(at: indexURL(in: directory))
    }

    static func bounded(
        _ entries: [String: ArchivedThreadSummaryIndex.Entry]
    ) -> [String: ArchivedThreadSummaryIndex.Entry] {
        let retainedEntries = entries.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(ArchivedThreadSummaryIndex.maximumEntries)
        return Dictionary(uniqueKeysWithValues: retainedEntries.map { ($0.id.uuidString, $0) })
    }

    private static func indexURL(in directory: URL) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
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
