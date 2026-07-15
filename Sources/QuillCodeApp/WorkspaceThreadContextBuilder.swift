import Foundation
import QuillCodeCore

struct WorkspaceThreadContextSnapshot: Equatable, Sendable {
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]
}

enum WorkspaceThreadContextBuilder {
    static func snapshot(
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
        personality: QuillCodePersonality = .defaultValue,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceThreadCreationContext {
        let snapshot = snapshot(projectID: projectID, projects: projects, globalMemories: globalMemories)
        return WorkspaceThreadCreationContext(
            projectID: projectID,
            mode: mode,
            model: model,
            personality: personality,
            instructions: snapshot.instructions,
            memories: snapshot.memories
        )
    }

    static func worktreeOpenContext(
        path: String,
        branch: String,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        personality: QuillCodePersonality = .defaultValue,
        projects: [ProjectRef],
        globalMemories: [MemoryNote]
    ) -> WorkspaceWorktreeOpenContext {
        let snapshot = snapshot(projectID: projectID, projects: projects, globalMemories: globalMemories)
        return WorkspaceWorktreeOpenContext(
            path: path,
            branch: branch,
            projectID: projectID,
            mode: mode,
            model: model,
            personality: personality,
            instructions: snapshot.instructions,
            memories: snapshot.memories
        )
    }
}
