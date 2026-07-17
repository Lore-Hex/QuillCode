import Foundation
import QuillCodeCore
import QuillCodePersistence
import QuillCodeTools

enum WorkspaceProjectContextRefresher {
    static func refreshLocalProjectMetadata(
        projectID: UUID?,
        projects: inout [ProjectRef],
        hookTrustStore: ProjectHookTrustFileStore? = nil
    ) {
        guard let projectID,
              let index = projects.firstIndex(where: { $0.id == projectID }),
              !projects[index].isRemote
        else {
            return
        }

        let rootURL = URL(fileURLWithPath: projects[index].path)
        applyMetadata(
            WorkspaceProjectMetadataLoader.loadLocal(
                from: rootURL,
                hookTrustStore: hookTrustStore
            ),
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
        personality: QuillCodePersonality = .defaultValue,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadCreationContext {
        contextSource(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        ).threadCreation(mode: mode, model: model, personality: personality)
    }

    static func worktreeOpenContext(
        request: WorkspaceWorktreeCreateRequest,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        personality: QuillCodePersonality = .defaultValue,
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
            model: model,
            personality: personality
        )
    }

    static func worktreeOpenContext(
        request: WorkspaceWorktreeOpenRequest,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        personality: QuillCodePersonality = .defaultValue,
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
            model: model,
            personality: personality
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
            scope: .instructionsAndMemories
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
            scope: .memoriesOnly
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
        scope: ThreadContextSyncScope
    ) {
        // Incognito threads deliberately carry NO workspace instructions/memories — the factory's
        // empty arrays are the intended state, and the per-send sync must not refill them from the
        // project/global context (private questions shouldn't be colored by durable workspace notes,
        // and nothing about the workspace should ride along to the provider).
        guard !thread.runtimeContext.isIncognito else { return }
        let snapshot = contextSource(
            projectID: thread.projectID ?? fallbackProjectID,
            projects: projects,
            globalMemories: globalMemories
        ).snapshot()
        scope.apply(snapshot, to: &thread)
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

private enum ThreadContextSyncScope {
    case instructionsAndMemories
    case memoriesOnly

    func apply(_ snapshot: WorkspaceThreadContextSnapshot, to thread: inout ChatThread) {
        switch self {
        case .instructionsAndMemories:
            thread.instructions = snapshot.instructions
            thread.memories = snapshot.memories
        case .memoriesOnly:
            thread.memories = snapshot.memories
        }
    }
}
