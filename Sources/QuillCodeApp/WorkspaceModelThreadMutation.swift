import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func appendNotice(_ summary: String) {
        mutateSelectedThread { thread in
            WorkspaceThreadNoticeAppender.appendNotice(summary, to: &thread)
        }
    }

    func mutateSelectedThread(_ update: (inout ChatThread) -> Void) {
        guard let selectedThreadID = root.selectedThreadID,
              let index = mutateThread(selectedThreadID, update)
        else {
            return
        }
        root.selectedThreadID = root.threads[index].id
        refreshTopBar(agentStatus: root.topBar.agentStatus)
    }

    func selectedSidebarThreadIDs() -> [UUID] {
        let resolution = WorkspaceSidebarSelectionEngine.resolve(
            state: sidebarSelection,
            orderedSidebarThreadIDs: filteredSidebarItems().map(\.id),
            validThreadIDs: validThreadIDs()
        )
        sidebarSelection = resolution.state
        return resolution.selectedThreadIDs
    }

    func filteredSidebarItems() -> [SidebarItem] {
        if let activeSearch = sidebarSavedSearches.first(where: { $0.id == activeSidebarSavedSearchID }) {
            return root.allSidebarItems.filter {
                SidebarThreadListBuilder.matches($0, query: activeSearch.query)
            }
        }
        return root.allSidebarItems.filter {
            sidebarFilter.includes(isPinned: $0.isPinned, isArchived: $0.isArchived)
        }
    }

    func validThreadIDs() -> Set<UUID> {
        Set(root.threads.map(\.id))
    }

    @discardableResult
    func mutateThread(_ id: UUID, _ update: (inout ChatThread) -> Void) -> Int? {
        guard let index = threadPersistence.mutate(id, threads: &root.threads, update: update) else {
            return nil
        }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return index
    }

    func updateThreadFromAgentRun(_ thread: ChatThread) {
        var thread = thread
        // A destroyed ephemeral thread must STAY destroyed: an in-flight send's progress callbacks
        // carry the run's own thread snapshot, and upserting it would resurrect an incognito/side
        // conversation the user already navigated away from (the UI promised it was gone). The
        // navigation path cancels the owning task; this guard covers the callbacks that race it.
        if thread.runtimeContext.isEphemeral,
           !root.threads.contains(where: { $0.id == thread.id }) {
            return
        }
        // Agent sessions operate on a send-start thread snapshot. Composer drafts are UI/model-owned
        // state, so progress and completion snapshots must never resurrect a draft that was sent,
        // cleared, or edited while the run was active.
        thread.composerDraft = root.threads.first { $0.id == thread.id }?.composerDraft ?? thread.composerDraft
        thread.composerAttachments = root.threads.first { $0.id == thread.id }?.composerAttachments
            ?? thread.composerAttachments
        let result = WorkspaceThreadLifecycleEngine.applyAgentRunThreadUpdate(
            thread,
            threads: &root.threads,
            projects: root.projects,
            selectedThreadID: root.selectedThreadID,
            selectedProjectID: root.selectedProjectID
        )
        root.selectedThreadID = result.selectedThreadID
        root.selectedProjectID = result.selectedProjectID
        if result.didSelectUpdatedThread {
            syncTerminalSessionToSelectedProject()
            touchProject(root.selectedProjectID)
            saveProjects()
        }
    }
}
