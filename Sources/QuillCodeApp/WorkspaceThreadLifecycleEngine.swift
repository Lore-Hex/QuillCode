import Foundation
import QuillCodeCore

struct WorkspaceThreadLifecycleEngine {
    struct ArchiveResult: Sendable, Hashable {
        var changedThread: ChatThread
        var selectedThreadID: UUID?
    }

    struct UnarchiveResult: Sendable, Hashable {
        var changedThread: ChatThread
        var projectID: UUID?
    }

    struct DeleteResult: Sendable, Hashable {
        var removedThread: ChatThread
        var selectedThreadID: UUID?
    }

    struct BulkMutationResult: Sendable, Hashable {
        var changedThreads: [ChatThread]
    }

    struct BulkDeleteResult: Sendable, Hashable {
        var removedThreads: [ChatThread]
    }

    static func renameThread(
        _ id: UUID,
        to title: String,
        threads: inout [ChatThread],
        now: Date = Date()
    ) -> ChatThread? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = threads.firstIndex(where: { $0.id == id })
        else {
            return nil
        }
        threads[index].title = trimmed
        threads[index].updatedAt = now
        return threads[index]
    }

    static func togglePinThread(
        _ id: UUID,
        threads: inout [ChatThread],
        now: Date = Date()
    ) -> ChatThread? {
        guard let index = threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        threads[index].isPinned.toggle()
        threads[index].updatedAt = now
        return threads[index]
    }

    static func archiveThread(
        _ id: UUID,
        threads: inout [ChatThread],
        selectedThreadID: UUID?,
        now: Date = Date()
    ) -> ArchiveResult? {
        guard let index = threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let archivedProjectID = threads[index].projectID
        threads[index].isArchived = true
        threads[index].updatedAt = now
        let nextSelection = selectedThreadID == id
            ? newestUnarchivedThreadID(in: threads, projectID: archivedProjectID)
            : selectedThreadID
        return ArchiveResult(
            changedThread: threads[index],
            selectedThreadID: nextSelection
        )
    }

    static func unarchiveThread(
        _ id: UUID,
        threads: inout [ChatThread],
        now: Date = Date()
    ) -> UnarchiveResult? {
        guard let index = threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        threads[index].isArchived = false
        threads[index].updatedAt = now
        return UnarchiveResult(
            changedThread: threads[index],
            projectID: threads[index].projectID
        )
    }

    static func deleteThread(
        _ id: UUID,
        threads: inout [ChatThread],
        selectedThreadID: UUID?
    ) -> DeleteResult? {
        guard let index = threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = threads.remove(at: index)
        let nextSelection = selectedThreadID == id
            ? newestUnarchivedThreadID(in: threads, projectID: removed.projectID)
            : selectedThreadID
        return DeleteResult(
            removedThread: removed,
            selectedThreadID: nextSelection
        )
    }

    static func archiveThreads(
        _ ids: [UUID],
        threads: inout [ChatThread],
        now: Date = Date()
    ) -> BulkMutationResult? {
        let targetIDs = Set(ids)
        guard !targetIDs.isEmpty else { return nil }
        var changedThreads: [ChatThread] = []
        for index in threads.indices where targetIDs.contains(threads[index].id) {
            threads[index].isArchived = true
            threads[index].isPinned = false
            threads[index].updatedAt = now
            changedThreads.append(threads[index])
        }
        return changedThreads.isEmpty ? nil : BulkMutationResult(changedThreads: changedThreads)
    }

    static func unarchiveThreads(
        _ ids: [UUID],
        threads: inout [ChatThread],
        now: Date = Date()
    ) -> BulkMutationResult? {
        let targetIDs = Set(ids)
        guard !targetIDs.isEmpty else { return nil }
        var changedThreads: [ChatThread] = []
        for index in threads.indices where targetIDs.contains(threads[index].id) {
            threads[index].isArchived = false
            threads[index].updatedAt = now
            changedThreads.append(threads[index])
        }
        return changedThreads.isEmpty ? nil : BulkMutationResult(changedThreads: changedThreads)
    }

    static func deleteThreads(
        _ ids: [UUID],
        threads: inout [ChatThread]
    ) -> BulkDeleteResult? {
        let targetIDs = Set(ids)
        guard !targetIDs.isEmpty else { return nil }
        var removedThreads: [ChatThread] = []
        threads.removeAll { thread in
            guard targetIDs.contains(thread.id) else { return false }
            removedThreads.append(thread)
            return true
        }
        return removedThreads.isEmpty ? nil : BulkDeleteResult(removedThreads: removedThreads)
    }

    static func newestUnarchivedThreadID(in threads: [ChatThread], projectID: UUID?) -> UUID? {
        threads
            .filter { !$0.isArchived && $0.projectID == projectID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .id
    }
}
