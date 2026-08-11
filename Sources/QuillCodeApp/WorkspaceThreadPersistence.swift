import Foundation
import QuillCodeCore
import QuillCodePersistence

struct WorkspaceThreadPersistence {
    let store: JSONThreadStore?
    let composerDraftStore: ComposerDraftCheckpointStore?
    let now: @Sendable () -> Date
    let issueTracker: WorkspaceThreadPersistenceIssueTracker

    init(
        store: JSONThreadStore?,
        composerDraftStore: ComposerDraftCheckpointStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        issueTracker: WorkspaceThreadPersistenceIssueTracker = WorkspaceThreadPersistenceIssueTracker()
    ) {
        self.store = store
        self.composerDraftStore = composerDraftStore
        self.now = now
        self.issueTracker = issueTracker
    }

    func save(_ thread: ChatThread) {
        guard !thread.runtimeContext.isEphemeral, let store else { return }
        do {
            try store.save(thread)
            issueTracker.recordSuccess(for: thread.id)
        } catch {
            issueTracker.recordFailure(for: thread.id)
        }
    }

    func saveOrThrow(_ thread: ChatThread) throws {
        guard !thread.runtimeContext.isEphemeral, let store else { return }
        do {
            try store.save(thread)
            issueTracker.recordSuccess(for: thread.id)
        } catch {
            issueTracker.recordFailure(for: thread.id)
            throw error
        }
    }

    func save(_ threads: [ChatThread]) {
        for thread in threads {
            save(thread)
        }
    }

    func delete(_ id: UUID) {
        do {
            try store?.delete(id)
            try composerDraftStore?.delete(for: id)
            issueTracker.recordSuccess(for: id)
        } catch {
            issueTracker.recordFailure(for: id)
        }
    }

    func composerDraft(for thread: ChatThread) -> String? {
        guard !thread.runtimeContext.isEphemeral, let composerDraftStore else {
            return thread.composerDraft
        }
        do {
            guard let checkpoint = try composerDraftStore.load(for: thread.id) else {
                return thread.composerDraft
            }
            return checkpoint.draft
        } catch {
            issueTracker.recordFailure(for: thread.id)
            return thread.composerDraft
        }
    }

    func saveComposerDraft(in thread: ChatThread) {
        guard !thread.runtimeContext.isEphemeral else { return }
        guard let composerDraftStore else {
            save(thread)
            return
        }
        do {
            if let store, !store.contains(thread.id) {
                try store.save(thread)
            }
            try composerDraftStore.save(thread.composerDraft, for: thread.id)
            issueTracker.recordSuccess(for: thread.id)
        } catch {
            // The established full-thread store remains a durable fallback when the lightweight
            // checkpoint path is unavailable or the draft exceeds its deliberately small bound.
            let removedStaleCheckpoint: Bool
            do {
                try composerDraftStore.delete(for: thread.id)
                removedStaleCheckpoint = true
            } catch {
                removedStaleCheckpoint = false
            }
            do {
                guard let store else { throw CocoaError(.fileNoSuchFile) }
                try store.save(thread)
                if removedStaleCheckpoint {
                    issueTracker.recordSuccess(for: thread.id)
                } else {
                    issueTracker.recordFailure(for: thread.id)
                }
            } catch {
                issueTracker.recordFailure(for: thread.id)
            }
        }
    }

    func pendingComposerDraft() -> String? {
        try? composerDraftStore?.load(for: nil)?.draft
    }

    func savePendingComposerDraft(_ draft: String?) {
        try? composerDraftStore?.save(draft, for: nil)
    }

    func deletePendingComposerDraft() {
        try? composerDraftStore?.delete(for: nil)
    }

    @discardableResult
    func mutate(
        _ id: UUID,
        threads: inout [ChatThread],
        update: (inout ChatThread) -> Void
    ) -> Int? {
        guard let index = threads.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        update(&threads[index])
        threads[index].updatedAt = now()
        save(threads[index])
        return index
    }
}
