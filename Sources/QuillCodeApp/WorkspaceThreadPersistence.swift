import Foundation
import QuillCodeCore
import QuillCodePersistence

struct WorkspaceThreadPersistence {
    let store: JSONThreadStore?
    let now: @Sendable () -> Date
    let issueTracker: WorkspaceThreadPersistenceIssueTracker

    init(
        store: JSONThreadStore?,
        now: @escaping @Sendable () -> Date = Date.init,
        issueTracker: WorkspaceThreadPersistenceIssueTracker = WorkspaceThreadPersistenceIssueTracker()
    ) {
        self.store = store
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
        guard let store else { return }
        do {
            try store.delete(id)
            issueTracker.recordSuccess(for: id)
        } catch {
            issueTracker.recordFailure(for: id)
        }
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
