import QuillCodeCore

struct WorkspaceMemoryContextUpdate: Sendable, Hashable {
    let memories: [MemoryNote]
    let event: ThreadEvent
}

struct WorkspaceMemoryContextUpdatePlanner {
    static func memoryChanged(
        memories: [MemoryNote],
        summary: String,
        relativePath: String
    ) -> WorkspaceMemoryContextUpdate {
        WorkspaceMemoryContextUpdate(
            memories: memories,
            event: ThreadEvent(
                kind: .notice,
                summary: summary,
                payloadJSON: relativePath
            )
        )
    }

    static func globalMemoryChanged(
        memories: [MemoryNote],
        summary: String,
        relativePath: String
    ) -> WorkspaceMemoryContextUpdate {
        memoryChanged(memories: memories, summary: summary, relativePath: relativePath)
    }
}
