import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func togglePinSelectedThread() {
        withSelectedThreadID(togglePinThread)
    }

    public func archiveSelectedThread() {
        withSelectedThreadID(archiveThread)
    }

    @discardableResult
    public func renameThread(_ id: UUID, to title: String) -> Bool {
        updateAndSaveThread { threads in
            WorkspaceThreadLifecycleEngine.renameThread(id, to: title, threads: &threads)
        } != nil
    }

    public func togglePinThread(_ id: UUID) {
        _ = updateAndSaveThread { threads in
            WorkspaceThreadLifecycleEngine.togglePinThread(id, threads: &threads)
        }
    }

    @discardableResult
    public func setPinThread(_ id: UUID, isPinned: Bool) -> Bool {
        updateAndSaveThread { threads in
            WorkspaceThreadLifecycleEngine.setPinThread(id, isPinned: isPinned, threads: &threads)
        } != nil
    }

    public func archiveThread(_ id: UUID) {
        applyNavigationLifecycleChange {
            guard let result = updateThreadLifecycle({ threads in
                WorkspaceThreadLifecycleEngine.archiveThread(
                    id,
                    threads: &threads,
                    selectedThreadID: root.selectedThreadID
                )
            }) else { return false }

            applyLifecycleSelection(result.selectedThreadID)
            persistChangedThread(result.changedThread)
            return true
        }
    }

    @discardableResult
    public func unarchiveThread(_ id: UUID) -> Bool {
        applyNavigationLifecycleChange {
            guard let result = updateThreadLifecycle({
                WorkspaceThreadLifecycleEngine.unarchiveThread(id, threads: &$0)
            }) else { return false }

            applyThreadDraftSelection(to: id)
            root.selectedThreadID = id
            root.selectedProjectID = knownProjectID(result.projectID)
            touchProject(root.selectedProjectID)
            saveProjects()
            persistChangedThread(result.changedThread)
            return true
        }
    }

    @discardableResult
    public func deleteThread(_ id: UUID) -> Bool {
        applyNavigationLifecycleChange {
            guard let result = updateThreadLifecycle({ threads in
                WorkspaceThreadLifecycleEngine.deleteThread(
                    id,
                    threads: &threads,
                    selectedThreadID: root.selectedThreadID
                )
            }) else { return false }

            threadPersistence.delete(id)
            applyLifecycleSelection(result.selectedThreadID, removing: id)
            syncSelectedProjectAfterDelete()
            saveProjects()
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            pruneNavigationHistory()
            return true
        }
    }

    @discardableResult
    public func clearThread(_ id: UUID) -> Bool {
        guard let result = updateThreadLifecycle({
            WorkspaceThreadLifecycleEngine.clearThread(id, threads: &$0)
        }) else {
            return false
        }

        clearComposerDraft(for: id)
        persistChangedThread(result.changedThread)
        return true
    }

    @discardableResult
    private func updateAndSaveThread(
        _ mutation: (inout [ChatThread]) -> ChatThread?
    ) -> ChatThread? {
        guard let changedThread = updateThreadLifecycle(mutation) else { return nil }
        persistChangedThread(changedThread)
        return changedThread
    }

    private func withSelectedThreadID(_ action: (UUID) -> Void) {
        guard let selectedThreadID = root.selectedThreadID else { return }
        action(selectedThreadID)
    }

    @discardableResult
    private func applyNavigationLifecycleChange(_ change: () -> Bool) -> Bool {
        let previousLocation = currentNavigationLocation
        guard change() else { return false }
        recordNavigationTransition(from: previousLocation)
        return true
    }

    private func updateThreadLifecycle<Result>(
        _ mutation: (inout [ChatThread]) -> Result?
    ) -> Result? {
        var threads = root.threads
        guard let result = mutation(&threads) else { return nil }
        root.threads = threads
        return result
    }

    private func applyLifecycleSelection(_ selectedThreadID: UUID?, removing removed: UUID? = nil) {
        applyThreadDraftSelection(to: selectedThreadID, removing: removed)
        root.selectedThreadID = selectedThreadID
    }

    private func persistChangedThread(_ thread: ChatThread) {
        threadPersistence.save(thread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    private func syncSelectedProjectAfterDelete() {
        if let selectedThread {
            root.selectedProjectID = knownProjectID(selectedThread.projectID)
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
    }
}
