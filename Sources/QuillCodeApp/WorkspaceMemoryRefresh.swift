import Foundation
import QuillCodeCore

struct WorkspaceMemoryRefresh: Sendable, Equatable {
    let global: [MemoryNote]?
    let project: [MemoryNote]?

    static let none = WorkspaceMemoryRefresh(global: nil, project: nil)

    static func global(from directory: URL) -> WorkspaceMemoryRefresh {
        WorkspaceMemoryRefresh(
            global: MemoryNoteLoader.loadGlobal(from: directory),
            project: nil
        )
    }

    static func project(from projectRoot: URL) -> WorkspaceMemoryRefresh {
        WorkspaceMemoryRefresh(
            global: nil,
            project: MemoryNoteLoader.loadProject(from: projectRoot)
        )
    }

    static func project(_ memories: [MemoryNote]?) -> WorkspaceMemoryRefresh {
        WorkspaceMemoryRefresh(global: nil, project: memories)
    }
}
