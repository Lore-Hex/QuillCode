import Foundation
import QuillCodeCore
import QuillCodeTools

struct WorkspaceThreadContextSnapshot: Equatable, Sendable {
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
}

enum WorkspaceProjectContextRefresher {
    static func refreshLocalProjectMetadata(
        projectID: UUID?,
        projects: inout [ProjectRef]
    ) {
        guard let projectID,
              let index = projects.firstIndex(where: { $0.id == projectID }),
              !projects[index].isRemote
        else {
            return
        }

        let rootURL = URL(fileURLWithPath: projects[index].path)
        WorkspaceProjectEngine.applyMetadata(
            WorkspaceProjectMetadataLoader.loadLocal(from: rootURL),
            to: projectID,
            projects: &projects,
            includeLocalExtensions: true
        )
    }

    static func refreshRemoteProjectContext(
        projectID: UUID,
        projects: inout [ProjectRef],
        executor: SSHRemoteShellExecutor
    ) throws -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }),
              projects[index].isRemote
        else {
            return false
        }

        let metadata = try WorkspaceProjectMetadataLoader.loadRemote(
            connection: projects[index].connection,
            executor: executor
        )
        WorkspaceProjectEngine.applyMetadata(metadata, to: projectID, projects: &projects, includeLocalExtensions: false)
        return true
    }

    static func threadContext(
        projectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadContextSnapshot {
        let resolver = WorkspaceContextResolver(
            projects: projects,
            globalMemories: globalMemories,
            selectedProject: nil
        )
        return WorkspaceThreadContextSnapshot(
            instructions: resolver.instructions(for: projectID),
            memories: resolver.memoryNotes(for: projectID)
        )
    }

    static func threadCreationContext(
        projectID: UUID?,
        mode: AgentMode,
        model: String,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadCreationContext {
        let snapshot = threadContext(projectID: projectID, projects: projects, globalMemories: globalMemories)
        return WorkspaceThreadCreationContext(
            projectID: projectID,
            mode: mode,
            model: model,
            instructions: snapshot.instructions,
            memories: snapshot.memories
        )
    }

    static func worktreeOpenContext(
        request: WorkspaceWorktreeCreateRequest,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceWorktreeOpenContext {
        let snapshot = threadContext(projectID: projectID, projects: projects, globalMemories: globalMemories)
        return WorkspaceWorktreeOpenContext(
            request: request,
            projectID: projectID,
            mode: mode,
            model: model,
            instructions: snapshot.instructions,
            memories: snapshot.memories
        )
    }

    static func syncThreadContext(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) {
        let snapshot = threadContext(
            projectID: thread.projectID ?? fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        )
        thread.instructions = snapshot.instructions
        thread.memories = snapshot.memories
    }

    static func syncThreadMemories(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) {
        let snapshot = threadContext(
            projectID: thread.projectID ?? fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        )
        thread.memories = snapshot.memories
    }

    static func globalMemories(directory: URL?) -> [MemoryNote] {
        WorkspaceMemoryEngine.loadGlobal(from: directory)
    }
}
