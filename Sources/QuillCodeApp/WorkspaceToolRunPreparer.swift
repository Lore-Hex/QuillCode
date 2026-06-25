import Foundation
import QuillCodeCore

struct WorkspacePreparedToolRun: Sendable, Hashable {
    let threadID: UUID
    let projectID: UUID?
}

enum WorkspaceToolRunPreparer {
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
    ) -> WorkspacePreparedToolRun {
        WorkspaceProjectContextRefresher.syncThreadContext(
            &thread,
            fallbackProjectID: fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        )
        return WorkspacePreparedToolRun(
            threadID: thread.id,
            projectID: effectiveProjectID(thread: thread, fallbackProjectID: fallbackProjectID)
        )
    }
}
