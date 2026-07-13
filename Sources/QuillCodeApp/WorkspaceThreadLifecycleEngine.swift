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

    struct ClearResult: Sendable, Hashable {
        var changedThread: ChatThread
    }

    struct BulkMutationResult: Sendable, Hashable {
        var changedThreads: [ChatThread]
    }

    struct BulkDeleteResult: Sendable, Hashable {
        var removedThreads: [ChatThread]
    }

    struct AgentRunThreadUpdateResult: Sendable, Hashable {
        var selectedThreadID: UUID?
        var selectedProjectID: UUID?
        var didSelectUpdatedThread: Bool
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

    static func setPinThread(
        _ id: UUID,
        isPinned: Bool,
        threads: inout [ChatThread],
        now: Date = Date()
    ) -> ChatThread? {
        guard let index = threads.firstIndex(where: { $0.id == id }),
              threads[index].isPinned != isPinned
        else {
            return nil
        }
        threads[index].isPinned = isPinned
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

    static func clearThread(
        _ id: UUID,
        threads: inout [ChatThread],
        now: Date = Date()
    ) -> ClearResult? {
        guard let index = threads.firstIndex(where: { $0.id == id }),
              !threads[index].messages.isEmpty
                || !threads[index].events.isEmpty
                || !threads[index].subagentRuns.isEmpty
                || !threads[index].followUpQueue.isEmpty
                || threads[index].composerDraft != nil
                || !threads[index].composerAttachments.isEmpty
        else {
            return nil
        }

        threads[index].messages = []
        threads[index].events = []
        threads[index].subagentRuns = []
        threads[index].followUpQueue = []
        threads[index].composerDraft = nil
        threads[index].composerAttachments = []
        threads[index].updatedAt = now
        return ClearResult(changedThread: threads[index])
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

    static func applyAgentRunThreadUpdate(
        _ thread: ChatThread,
        threads: inout [ChatThread],
        projects: [ProjectRef],
        selectedThreadID: UUID?,
        selectedProjectID: UUID?
    ) -> AgentRunThreadUpdateResult {
        upsertThread(thread, threads: &threads)
        if let selectedThreadID,
           threads.contains(where: { $0.id == selectedThreadID }) {
            return AgentRunThreadUpdateResult(
                selectedThreadID: selectedThreadID,
                selectedProjectID: selectedProjectID,
                didSelectUpdatedThread: false
            )
        }
        return AgentRunThreadUpdateResult(
            selectedThreadID: thread.id,
            selectedProjectID: WorkspaceProjectEngine.knownProjectID(thread.projectID, projects: projects),
            didSelectUpdatedThread: true
        )
    }

    static func newestUnarchivedThreadID(in threads: [ChatThread], projectID: UUID?) -> UUID? {
        threads
            .filter { !$0.isArchived && $0.projectID == projectID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?
            .id
    }

    private static func upsertThread(_ thread: ChatThread, threads: inout [ChatThread]) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            // The follow-up queue is model/UI-owned state, not conversation state the agent
            // produces — its snapshot in the incoming (agent) copy is stale (captured at
            // send-start, before any mid-run enqueue). Preserve the live in-memory queue so a
            // follow-up submitted DURING the run survives the agent's authoritative overwrite
            // and is still present for the turn-boundary drain.
            var updated = thread
            updated.followUpQueue = threads[index].followUpQueue
            updated.composerDraft = threads[index].composerDraft
            updated.composerAttachments = threads[index].composerAttachments
            // Goals are also UI-owned durable state. A slash command can update or clear one while
            // an agent is running, so the send-start agent snapshot must not overwrite that change.
            updated.goal = threads[index].goal
            threads[index] = updated
        } else {
            threads.insert(thread, at: 0)
        }
    }
}
