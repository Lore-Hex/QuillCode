import Foundation
import QuillCodeCore

struct WorkspacePreparedThreadContext: Sendable, Hashable {
    let threadID: UUID
    let projectID: UUID?
}

enum WorkspaceThreadContextPreparer {
    static func effectiveProjectID(
        thread: ChatThread?,
        fallbackProjectID: UUID?
    ) -> UUID? {
        thread?.projectID ?? fallbackProjectID
    }

    static func syncThreadContext(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspacePreparedThreadContext {
        WorkspaceProjectContextRefresher.syncThreadContext(
            &thread,
            fallbackProjectID: fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        )
        return WorkspacePreparedThreadContext(
            threadID: thread.id,
            projectID: effectiveProjectID(
                thread: thread,
                fallbackProjectID: fallbackProjectID
            )
        )
    }
}
