import Foundation
import QuillCodeCore
import QuillCodeTools

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
        WorkspaceProjectEngine.applyMetadata(
            metadata,
            to: projectID,
            projects: &projects,
            includeLocalExtensions: false
        )
        return true
    }

    static func threadContext(
        projectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadContextSnapshot {
        WorkspaceThreadContextBuilder.snapshot(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        )
    }

    static func threadCreationContext(
        projectID: UUID?,
        mode: AgentMode,
        model: String,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadCreationContext {
        WorkspaceThreadContextBuilder.threadCreationContext(
            projectID: projectID,
            mode: mode,
            model: model,
            projects: projects,
            globalMemories: globalMemories
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
        WorkspaceThreadContextBuilder.worktreeOpenContext(
            path: request.path,
            branch: request.branch,
            projectID: projectID,
            mode: mode,
            model: model,
            projects: projects,
            globalMemories: globalMemories
        )
    }

    static func worktreeOpenContext(
        request: WorkspaceWorktreeOpenRequest,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceWorktreeOpenContext {
        WorkspaceThreadContextBuilder.worktreeOpenContext(
            path: request.path,
            branch: "",
            projectID: projectID,
            mode: mode,
            model: model,
            projects: projects,
            globalMemories: globalMemories
        )
    }

    static func syncThreadContext(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) {
        let snapshot = snapshot(for: thread, fallbackProjectID: fallbackProjectID, projects: projects, globalMemories: globalMemories)
        thread.instructions = snapshot.instructions
        thread.memories = snapshot.memories
    }

    static func syncThreadMemories(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) {
        let snapshot = snapshot(for: thread, fallbackProjectID: fallbackProjectID, projects: projects, globalMemories: globalMemories)
        thread.memories = snapshot.memories
    }

    static func globalMemories(directory: URL?) -> [MemoryNote] {
        WorkspaceMemoryEngine.loadGlobal(from: directory)
    }

    private static func snapshot(
        for thread: ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadContextSnapshot {
        threadContext(
            projectID: thread.projectID ?? fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        )
    }
}
