import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    @discardableResult
    public func newChat(projectID: UUID? = nil) -> UUID {
        let effectiveProjectID = knownProjectID(projectID ?? root.selectedProjectID)
        refreshProjectMetadata(effectiveProjectID)
        let thread = WorkspaceThreadCreationEngine.newThread(context: WorkspaceProjectContextRefresher.threadCreationContext(
            projectID: effectiveProjectID,
            mode: root.config.mode,
            model: root.config.defaultModel,
            projects: root.projects,
            globalMemories: root.globalMemories
        ))
        return insertCreatedThread(thread, selectedProjectID: effectiveProjectID, saveThread: false)
    }

    @discardableResult
    public func forkFromLast() -> UUID? {
        guard let source = selectedThread, !source.messages.isEmpty else { return nil }
        let projectID = knownProjectID(source.projectID)
        let fork = WorkspaceThreadCreationEngine.forkThread(
            from: source,
            projectID: projectID
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

    public func selectThread(_ id: UUID) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    public func startSidebarSelection(selecting id: UUID? = nil) {
        sidebarSelection = WorkspaceSidebarSelectionEngine.start(
            selecting: id,
            state: sidebarSelection,
            validThreadIDs: validThreadIDs()
        )
    }

    public func clearSidebarSelection() {
        sidebarSelection = WorkspaceSidebarSelectionEngine.clear()
    }

    public func selectAllSidebarThreads() {
        sidebarSelection = WorkspaceSidebarSelectionEngine.selectAll(
            orderedThreadIDs: root.allSidebarItems.map(\.id)
        )
    }

    public func toggleSidebarThreadSelection(_ id: UUID) {
        guard let nextSelection = WorkspaceSidebarSelectionEngine.toggle(
            id,
            state: sidebarSelection,
            validThreadIDs: validThreadIDs()
        ) else { return }
        sidebarSelection = nextSelection
    }

    @discardableResult
    public func performSidebarBulkAction(_ kind: SidebarBulkActionKind) -> Bool {
        guard let plan = WorkspaceSidebarBulkActionPlanner.plan(
            kind: kind,
            selection: sidebarSelection,
            orderedSidebarThreadIDs: root.allSidebarItems.map(\.id),
            threads: root.threads,
            selectedThreadID: root.selectedThreadID
        ) else {
            return false
        }
        guard let result = WorkspaceSidebarBulkActionExecutor.execute(
            plan,
            threads: root.threads,
            projects: root.projects,
            selectedThreadID: root.selectedThreadID,
            selectedProjectID: root.selectedProjectID
        ) else {
            return false
        }

        sidebarSelection = result.nextSelection
        root.threads = result.threads
        root.selectedThreadID = result.selectedThreadID
        root.selectedProjectID = result.selectedProjectID
        threadPersistence.save(result.changedThreads)
        for thread in result.removedThreads {
            threadPersistence.delete(thread.id)
        }
        if result.shouldSyncTerminalSession {
            syncTerminalSessionToSelectedProject()
        }
        if let projectID = result.projectIDToTouch {
            touchProject(projectID)
        }
        if result.shouldSaveProjects {
            saveProjects()
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        }
        return true
    }

    public func togglePinSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        togglePinThread(selectedThreadID)
    }

    public func archiveSelectedThread() {
        guard let selectedThreadID = root.selectedThreadID else { return }
        archiveThread(selectedThreadID)
    }

    @discardableResult
    public func renameThread(_ id: UUID, to title: String) -> Bool {
        var threads = root.threads
        guard let changedThread = WorkspaceThreadLifecycleEngine.renameThread(
            id,
            to: title,
            threads: &threads
        ) else {
            return false
        }
        root.threads = threads
        threadPersistence.save(changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
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

    @discardableResult
    func insertCreatedThread(
        _ thread: ChatThread,
        selectedProjectID: UUID?,
        saveThread: Bool
    ) -> UUID {
        clearSidebarSelection()
        root.threads.insert(thread, at: 0)
        root.selectedThreadID = thread.id
        root.selectedProjectID = selectedProjectID
        syncTerminalSessionToSelectedProject()
        touchProject(selectedProjectID)
        saveProjects()
        if saveThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return thread.id
    }

    public func togglePinThread(_ id: UUID) {
        var threads = root.threads
        guard let changedThread = WorkspaceThreadLifecycleEngine.togglePinThread(
            id,
            threads: &threads
        ) else { return }
        root.threads = threads
        threadPersistence.save(changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    public func archiveThread(_ id: UUID) {
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.archiveThread(
            id,
            threads: &threads,
            selectedThreadID: root.selectedThreadID
        ) else { return }
        root.threads = threads
        root.selectedThreadID = result.selectedThreadID
        threadPersistence.save(result.changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
    }

    @discardableResult
    public func unarchiveThread(_ id: UUID) -> Bool {
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.unarchiveThread(
            id,
            threads: &threads
        ) else {
            return false
        }
        root.threads = threads
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(result.projectID)
        touchProject(root.selectedProjectID)
        saveProjects()
        threadPersistence.save(result.changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    @discardableResult
    public func deleteThread(_ id: UUID) -> Bool {
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.deleteThread(
            id,
            threads: &threads,
            selectedThreadID: root.selectedThreadID
        ) else {
            return false
        }
        root.threads = threads
        threadPersistence.delete(id)
        root.selectedThreadID = result.selectedThreadID
        if let selectedThread {
            root.selectedProjectID = knownProjectID(selectedThread.projectID)
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }
}
