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
    func hydrateThreadPayload(_ id: UUID) -> Bool {
        threadPersistence.hydrate(id, threads: &root.threads) != nil
    }

    @discardableResult
    func hydrateThreadPayloads<S: Sequence>(_ ids: S) -> Bool where S.Element == UUID {
        for id in ids where !hydrateThreadPayload(id) {
            return false
        }
        return true
    }

    @discardableResult
    func mutateThread(_ id: UUID, _ update: (inout ChatThread) -> Void) -> Int? {
        guard let index = threadPersistence.mutate(id, threads: &root.threads, update: update) else {
            return nil
        }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return index
    }

    func updateThreadFromAgentRun(
        _ thread: ChatThread,
        preserveMemoryContext: Bool = true
    ) {
        // Agent streaming keeps reasoning notices compact as it produces them, while the durable
        // store repairs legacy histories on load and save. Keep this hot path copy-on-write: it is
        // called at presentation cadence and must not rebuild the full event array on every update.
        var thread = thread
        // A destroyed ephemeral thread must STAY destroyed: an in-flight send's progress callbacks
        // carry the run's own thread snapshot, and upserting it would resurrect a confidential/side
        // conversation the user already navigated away from (the UI promised it was gone). The
        // navigation path cancels the owning task; this guard covers the callbacks that race it.
        if thread.runtimeContext.isEphemeral,
           !root.threads.contains(where: { $0.id == thread.id }) {
            return
        }
        // Agent sessions operate on a send-start thread snapshot. Composer drafts are UI/model-owned
        // state, so progress and completion snapshots must never resurrect a draft that was sent,
        // cleared, or edited while the run was active.
        if let liveThread = root.threads.first(where: { $0.id == thread.id }) {
            thread.composerDraft = liveThread.composerDraft
            thread.composerAttachments = liveThread.composerAttachments
            // The session's producer snapshot was captured before the model installed its durable
            // run generation. Only the owning model clears that checkpoint at a terminal boundary.
            thread.activeRunCheckpoint = liveThread.activeRunCheckpoint
            // Project context can refresh while an agent runs. A progress snapshot captured at
            // send start must not roll that newer model-owned context back.
            thread.instructions = liveThread.instructions
            if preserveMemoryContext {
                thread.memories = liveThread.memories
            }
        }
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

    func updateThreadFromAgentProgress(_ thread: ChatThread) -> WorkspaceAgentProgressThreadMutation? {
        if thread.runtimeContext.isEphemeral,
           !root.threads.contains(where: { $0.id == thread.id }) {
            return nil
        }
        let result = WorkspaceThreadLifecycleEngine.applyAgentRunProgressThreadUpdate(
            thread,
            threads: &root.threads,
            projects: root.projects,
            selectedThreadID: root.selectedThreadID,
            selectedProjectID: root.selectedProjectID
        )
        root.selectedThreadID = result.lifecycle.selectedThreadID
        root.selectedProjectID = result.lifecycle.selectedProjectID
        if result.lifecycle.didSelectUpdatedThread {
            syncTerminalSessionToSelectedProject()
            touchProject(root.selectedProjectID)
            saveProjects()
        }
        return result.mutation
    }
}
