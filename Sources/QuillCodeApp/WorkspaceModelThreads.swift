import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let context = WorkspaceProjectContextRefresher.threadCreationContext(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
        let thread = WorkspaceThreadCreationEngine.newThread(context: context)
        return insertCreatedThread(thread, selectedProjectID: effectiveProjectID, saveThread: false)
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        forkThread(strategy: .latestTurn)
    }

    @discardableResult
    func forkThread(strategy: WorkspaceThreadForkStrategy) -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let projectID = knownProjectID(source.projectID)
        let fork = WorkspaceThreadCreationEngine.forkThread(
            from: source,
            projectID: projectID,
            strategy: strategy
        )
        return insertCreatedThread(fork, selectedProjectID: projectID, saveThread: true)
    }

    @discardableResult
    public func compactContext() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let projectID = knownProjectID(source.projectID)
        let compacted = WorkspaceThreadCreationEngine.compactThread(
            from: source,
            projectID: projectID
        )
        return insertCreatedThread(compacted, selectedProjectID: projectID, saveThread: true)
    }

    @discardableResult
    public func duplicateThread(_ id: UUID) -> UUID? {
        guard let source = root.threads.first(where: { $0.id == id }) else { return nil }
        let projectID = knownProjectID(source.projectID)
        let duplicate = WorkspaceThreadCreationEngine.duplicateThread(
            source,
            projectID: projectID
        )
        return insertCreatedThread(duplicate, selectedProjectID: projectID, saveThread: true)
    }

    /// Binds the selected thread to a worktree so its agent runs operate in that isolated directory
    /// and branch instead of the shared project root. Persists through the shared thread-mutation
    /// helper. `base` records the ref this worktree was forked off (its land-back target).
    public func bindSelectedThreadToWorktree(path: String, branch: String, base: String? = nil) {
        mutateSelectedThread { thread in
            thread.worktree = WorktreeBinding(path: path, branch: branch, base: base)
            thread.updatedAt = Date()
        }
    }
}
