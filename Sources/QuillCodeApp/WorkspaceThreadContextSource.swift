import Foundation
import QuillCodeCore

struct WorkspaceThreadContextSource {
    var projectID: UUID?
    var projects: [ProjectRef]
    var globalMemories: [MemoryNote]

    func snapshot() -> WorkspaceThreadContextSnapshot {
        snapshot(projectID: projectID)
    }

    func threadCreation(
        mode: AgentMode,
        model: String,
        personality: QuillCodePersonality = .defaultValue
    ) -> WorkspaceThreadCreationContext {
        let snapshot = snapshot()
        return WorkspaceThreadCreationContext(
            projectID: projectID,
            mode: mode,
            model: model,
            personality: personality,
            instructions: snapshot.instructions,
            memories: snapshot.memories
        )
    }

    func worktreeOpen(
        path: String,
        branch: String,
        projectID: UUID,
        mode: AgentMode,
        model: String,
        personality: QuillCodePersonality = .defaultValue
    ) -> WorkspaceWorktreeOpenContext {
        let snapshot = snapshot(projectID: projectID)
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

    private func snapshot(projectID: UUID?) -> WorkspaceThreadContextSnapshot {
        WorkspaceThreadContextBuilder.snapshot(
            projectID: projectID,
            projects: projects,
            globalMemories: globalMemories
        )
    }
}
