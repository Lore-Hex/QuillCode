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
        applyMetadata(
            WorkspaceProjectMetadataLoader.loadLocal(from: rootURL),
            to: projectID,
            projects: &projects,
            source: .local
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
        applyMetadata(metadata, to: projectID, projects: &projects, source: .remote)
        return true
    }

    static func threadContext(
        projectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadContextSnapshot {
        contextSource(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        ).snapshot()
    }

    static func threadCreationContext(
        projectID: UUID?,
        mode: AgentMode,
        model: String,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadCreationContext {
        contextSource(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        ).threadCreation(mode: mode, model: model)
    }

    static func worktreeOpenContext(
        request: WorkspaceWorktreeCreateRequest,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceWorktreeOpenContext {
        contextSource(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        ).worktreeOpen(
            path: request.path,
            branch: request.branch,
            projectID: projectID,
            mode: mode,
            model: model
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
        contextSource(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        ).worktreeOpen(
            path: request.path,
            branch: "",
            projectID: projectID,
            mode: mode,
            model: model
        )
    }

    static func syncThreadContext(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) {
        syncThread(
            &thread,
            fallbackProjectID: fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories,
            includeInstructions: true
        )
    }

    static func syncThreadMemories(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) {
        syncThread(
            &thread,
            fallbackProjectID: fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories,
            includeInstructions: false
        )
    }

    static func globalMemories(directory: URL?) -> [MemoryNote] {
        WorkspaceMemoryEngine.loadGlobal(from: directory)
    }

    private static func applyMetadata(
        _ metadata: WorkspaceProjectMetadata,
        to projectID: UUID,
        projects: inout [ProjectRef],
        source: ProjectMetadataSource
    ) {
        WorkspaceProjectEngine.applyMetadata(
            metadata,
            to: projectID,
            projects: &projects,
            includeLocalExtensions: source.includesLocalExtensions
        )
    }

    private static func syncThread(
        _ thread: inout ChatThread,
        fallbackProjectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote],
        includeInstructions: Bool
    ) {
        let snapshot = contextSource(
            projectID: thread.projectID ?? fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        ).snapshot()
        if includeInstructions {
            thread.instructions = snapshot.instructions
        }
        thread.memories = snapshot.memories
    }

    private static func contextSource(
        projectID: UUID?,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadContextSource {
        WorkspaceThreadContextSource(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        )
    }

    private enum ProjectMetadataSource {
        case local
        case remote

        var includesLocalExtensions: Bool {
            self == .local
        }
    }
}
