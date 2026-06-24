import Foundation
import QuillCodeCore
import QuillCodePersistence

struct WorkspaceThreadPersistence {
    let store: JSONThreadStore?
    let now: @Sendable () -> Date

    init(store: JSONThreadStore?, now: @escaping @Sendable () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    func save(_ thread: ChatThread) {
        try? store?.save(thread)
    }

    func saveOrThrow(_ thread: ChatThread) throws {
        try store?.save(thread)
    }

    func save(_ threads: [ChatThread]) {
        for thread in threads {
            save(thread)
        }
    }

    func delete(_ id: UUID) {
        try? store?.delete(id)
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
