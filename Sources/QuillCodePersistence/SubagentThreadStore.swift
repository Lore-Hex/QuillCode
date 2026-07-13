import Foundation
import QuillCodeCore

/// Persists delegated worker transcripts outside the normal sidebar thread directory.
public struct SubagentThreadStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ thread: ChatThread) throws {
        try backingStore.save(thread)
    }

    public func load(_ id: UUID) throws -> ChatThread {
        try backingStore.load(id)
    }

    public func delete(_ id: UUID) throws {
        try backingStore.delete(id)
    }

    private var backingStore: JSONThreadStore {
        JSONThreadStore(directory: directory)
    }
}
