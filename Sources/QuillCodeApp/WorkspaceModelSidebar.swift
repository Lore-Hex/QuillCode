import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
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

    public func setSidebarFilter(_ filter: SidebarSavedFilterKind) {
        guard sidebarFilter != filter || activeSidebarSavedSearchID != nil else { return }
        sidebarFilter = filter
        activeSidebarSavedSearchID = nil
        clearSidebarSelection()
    }

    public func setSidebarSavedSearch(_ id: UUID) -> Bool {
        guard sidebarSavedSearches.contains(where: { $0.id == id }) else { return false }
        guard activeSidebarSavedSearchID != id else { return true }
        activeSidebarSavedSearchID = id
        clearSidebarSelection()
        return true
    }

    @discardableResult
    public func saveSidebarSavedSearch(title: String, query: String) -> SidebarSavedSearch? {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle = normalizedQuery.isEmpty ? "" : normalizedQuery
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedSearch = SidebarSavedSearch(
            title: normalizedTitle.isEmpty ? fallbackTitle : normalizedTitle,
            query: normalizedQuery
        )
        guard savedSearch.isValid else { return nil }

        if let existing = sidebarSavedSearches.first(where: {
            $0.title.caseInsensitiveCompare(savedSearch.title) == .orderedSame
                && $0.query.caseInsensitiveCompare(savedSearch.query) == .orderedSame
        }) {
            _ = setSidebarSavedSearch(existing.id)
            return existing
        }

        sidebarSavedSearches.append(savedSearch)
        activeSidebarSavedSearchID = savedSearch.id
        clearSidebarSelection()
        saveSidebarSavedSearches()
        return savedSearch
    }

    @discardableResult
    public func deleteSidebarSavedSearch(_ id: UUID) -> Bool {
        guard let index = sidebarSavedSearches.firstIndex(where: { $0.id == id }) else {
            return false
        }
        sidebarSavedSearches.remove(at: index)
        if activeSidebarSavedSearchID == id {
            activeSidebarSavedSearchID = nil
            sidebarFilter = .all
            clearSidebarSelection()
        }
        saveSidebarSavedSearches()
        return true
    }

    @discardableResult
    public func moveSidebarSavedSearch(_ id: UUID, direction: SidebarSavedSearchMoveDirection) -> Bool {
        guard let index = sidebarSavedSearches.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index - 1
        case .down:
            targetIndex = index + 1
        }
        guard sidebarSavedSearches.indices.contains(targetIndex) else {
            return false
        }
        sidebarSavedSearches.swapAt(index, targetIndex)
        saveSidebarSavedSearches()
        return true
    }

    public func selectAllSidebarThreads() {
        sidebarSelection = WorkspaceSidebarSelectionEngine.selectAll(
            orderedThreadIDs: filteredSidebarItems().map(\.id)
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
        if kind == .delete,
           selectedSidebarThreadIDs().contains(where: { agentRuns.isRunning($0) }) {
            setLastError("Stop running chats before deleting them.")
            return false
        }
        guard let plan = WorkspaceSidebarBulkActionPlanner.plan(
            kind: kind,
            selection: sidebarSelection,
            orderedSidebarThreadIDs: filteredSidebarItems().map(\.id),
            threads: root.threads,
            selectedThreadID: root.selectedThreadID
        ) else {
            return false
        }
        if case .archive(let ids) = plan.mutation {
            for id in ids {
                preserveDisposableWorktreeBeforeArchive(threadID: id)
            }
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
        // Bulk actions can move the selection off an incognito thread without going through
        // selectThread; discard it like every other exit path.
        if root.selectedThreadID != result.selectedThreadID {
            _ = discardIncognitoThreadOnExit()
        }
        applyThreadDraftSelection(to: result.selectedThreadID)
        for thread in result.removedThreads {
            threadDrafts = ComposerDraftStore.cleared(thread.id, drafts: threadDrafts)
        }
        root.selectedThreadID = result.selectedThreadID
        root.selectedProjectID = result.selectedProjectID
        threadPersistence.save(result.changedThreads)
        var removedSubagentAttachments: [ChatAttachment] = []
        for thread in result.removedThreads {
            threadPersistence.delete(thread.id)
            removedSubagentAttachments += removeSubagentArtifacts(for: thread)
            deleteWorktreeSnapshotIfPresent(in: thread)
        }
        removeManagedImagesIfUnreferenced(
            result.removedThreads.flatMap { thread in
                thread.composerAttachments
                    + thread.followUpQueue.flatMap(\.attachments)
                    + thread.messages.flatMap(\.attachments)
            } + removedSubagentAttachments
        )
        if !result.removedThreads.isEmpty {
            pruneNavigationHistory()
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
        if kind == .unpin {
            enforceManagedWorktreeRetention()
        }
        return true
    }
}
