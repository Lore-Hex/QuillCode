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
    func startForkThread(strategy: WorkspaceThreadForkStrategy) -> Bool {
        guard strategy == .summarizedContext, contextSummaryGenerator.isModelBacked else {
            return forkThread(strategy: strategy) != nil
        }
        guard let source = selectedThread, !source.messages.isEmpty else { return false }
        let sourceID = source.id
        setAgentStatus("Summarizing context")
        recordContextSummarySourceNotice(
            sourceID: sourceID,
            summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .forkSummary)
        )
        Task { @MainActor [weak self] in
            _ = await self?.forkThreadWithConfiguredSummary(sourceID: sourceID, strategy: strategy)
        }
        return true
    }

    @discardableResult
    func forkThreadWithConfiguredSummary(
        sourceID: UUID,
        strategy: WorkspaceThreadForkStrategy
    ) async -> UUID? {
        guard strategy == .summarizedContext,
              let source = root.threads.first(where: { $0.id == sourceID }),
              !source.messages.isEmpty
        else { return forkThread(strategy: strategy) }

        let projectID = knownProjectID(source.projectID)
        let summary = await configuredSummary(
            for: source,
            purpose: .forkSummary
        )
        recordContextSummarySourceNotice(
            sourceID: sourceID,
            summary: WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: summary,
                purpose: .forkSummary
            )
        )
        var fork = WorkspaceThreadCreationEngine.forkThread(
            from: source,
            projectID: projectID,
            strategy: strategy,
            summaryOverride: summary.summaryOverride
        )
        fork.events.append(
            WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
                outcome: summary,
                sourceTitle: source.title,
                purpose: .forkSummary
            )
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
    func startCompactContext() -> Bool {
        guard contextSummaryGenerator.isModelBacked else {
            return compactContext() != nil
        }
        guard let source = selectedThread, !source.messages.isEmpty else { return false }
        let sourceID = source.id
        setAgentStatus("Compacting context")
        recordContextSummarySourceNotice(
            sourceID: sourceID,
            summary: WorkspaceContextSummaryTelemetryPlanner.sourceStartSummary(purpose: .compact)
        )
        Task { @MainActor [weak self] in
            _ = await self?.compactContextWithConfiguredSummary(sourceID: sourceID)
        }
        return true
    }

    @discardableResult
    func compactContextWithConfiguredSummary(sourceID: UUID) async -> UUID? {
        guard let source = root.threads.first(where: { $0.id == sourceID }),
              !source.messages.isEmpty
        else { return nil }

        let projectID = knownProjectID(source.projectID)
        let summary = await configuredSummary(
            for: source,
            purpose: .compact
        )
        recordContextSummarySourceNotice(
            sourceID: sourceID,
            summary: WorkspaceContextSummaryTelemetryPlanner.sourceFinishedSummary(
                outcome: summary,
                purpose: .compact
            )
        )
        var compacted = WorkspaceThreadCreationEngine.compactThread(
            from: source,
            projectID: projectID,
            summaryOverride: summary.summaryOverride
        )
        compacted.events.append(
            WorkspaceContextSummaryTelemetryPlanner.continuationEvent(
                outcome: summary,
                sourceTitle: source.title,
                purpose: .compact
            )
        )
        return insertCreatedThread(compacted, selectedProjectID: projectID, saveThread: true)
    }

    private func configuredSummary(
        for source: ChatThread,
        purpose: WorkspaceContextSummaryPurpose
    ) async -> WorkspaceContextSummaryOutcome {
        let context = WorkspaceThreadSeedBuilder.summaryContext(from: source)
        let request = WorkspaceContextSummaryRequest(
            sourceTitle: source.title,
            context: context,
            purpose: purpose
        )
        do {
            return WorkspaceContextSummaryOutcome(
                summaryOverride: try await contextSummaryGenerator.summary(for: request),
                source: .model
            )
        } catch {
            return WorkspaceContextSummaryOutcome(
                summaryOverride: nil,
                source: .deterministicFallback,
                errorDescription: WorkspaceContextSummarySanitizer.diagnostic(from: error.localizedDescription)
            )
        }
    }

    private func recordContextSummarySourceNotice(sourceID: UUID, summary: String) {
        _ = mutateThread(sourceID) { thread in
            WorkspaceThreadNoticeAppender.appendNotice(summary, to: &thread)
        }
    }

    /// Stashes the outgoing thread's live draft and restores `newID`'s saved draft
    /// when a lifecycle change (archive/unarchive/delete) reassigns the selected
    /// thread without going through `selectThread`. Call BEFORE reassigning
    /// `root.selectedThreadID`. Pass `removing` to drop a deleted thread's draft.
    func applyThreadDraftSelection(to newID: UUID?, removing removed: UUID? = nil) {
        let outgoing = root.selectedThreadID
        if outgoing != newID {
            if let newID {
                let result = ComposerDraftStore.select(
                    outgoing: outgoing,
                    incoming: newID,
                    liveDraft: composer.draft,
                    drafts: threadDrafts
                )
                threadDrafts = result.drafts
                composer.draft = result.restoredDraft
            } else if let outgoing {
                // Selection cleared: stash the outgoing draft and empty the composer.
                if composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    threadDrafts[outgoing] = nil
                } else {
                    threadDrafts[outgoing] = composer.draft
                }
                composer.draft = ""
            }
        }
        // Prune a removed thread AFTER the swap so a deleted outgoing thread's live
        // draft is not re-stashed into an orphaned map entry.
        if let removed {
            threadDrafts = ComposerDraftStore.cleared(removed, drafts: threadDrafts)
        }
    }

    public func selectThread(_ id: UUID, recordsNavigation: Bool = true) {
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        let previousLocation = currentNavigationLocation
        let draftSwitch = ComposerDraftStore.select(
            outgoing: root.selectedThreadID,
            incoming: id,
            liveDraft: composer.draft,
            drafts: threadDrafts
        )
        threadDrafts = draftSwitch.drafts
        composer.draft = draftSwitch.restoredDraft
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(thread.projectID)
        syncTerminalSessionToSelectedProject()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        if recordsNavigation {
            recordNavigationTransition(from: previousLocation)
        }
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
        guard let plan = WorkspaceSidebarBulkActionPlanner.plan(
            kind: kind,
            selection: sidebarSelection,
            orderedSidebarThreadIDs: filteredSidebarItems().map(\.id),
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
        applyThreadDraftSelection(to: result.selectedThreadID)
        for thread in result.removedThreads {
            threadDrafts = ComposerDraftStore.cleared(thread.id, drafts: threadDrafts)
        }
        root.selectedThreadID = result.selectedThreadID
        root.selectedProjectID = result.selectedProjectID
        threadPersistence.save(result.changedThreads)
        for thread in result.removedThreads {
            threadPersistence.delete(thread.id)
        }
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
        let previousLocation = currentNavigationLocation
        clearSidebarSelection()
        let draftSwitch = ComposerDraftStore.select(
            outgoing: root.selectedThreadID,
            incoming: thread.id,
            liveDraft: composer.draft,
            drafts: threadDrafts
        )
        threadDrafts = draftSwitch.drafts
        composer.draft = draftSwitch.restoredDraft
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
        recordNavigationTransition(from: previousLocation)
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
        let previousLocation = currentNavigationLocation
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.archiveThread(
            id,
            threads: &threads,
            selectedThreadID: root.selectedThreadID
        ) else { return }
        root.threads = threads
        applyThreadDraftSelection(to: result.selectedThreadID)
        root.selectedThreadID = result.selectedThreadID
        threadPersistence.save(result.changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        recordNavigationTransition(from: previousLocation)
    }

    @discardableResult
    public func unarchiveThread(_ id: UUID) -> Bool {
        let previousLocation = currentNavigationLocation
        var threads = root.threads
        guard let result = WorkspaceThreadLifecycleEngine.unarchiveThread(
            id,
            threads: &threads
        ) else {
            return false
        }
        root.threads = threads
        applyThreadDraftSelection(to: id)
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(result.projectID)
        touchProject(root.selectedProjectID)
        saveProjects()
        threadPersistence.save(result.changedThread)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        recordNavigationTransition(from: previousLocation)
        return true
    }

    @discardableResult
    public func deleteThread(_ id: UUID) -> Bool {
        let previousLocation = currentNavigationLocation
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
        applyThreadDraftSelection(to: result.selectedThreadID, removing: id)
        root.selectedThreadID = result.selectedThreadID
        if let selectedThread {
            root.selectedProjectID = knownProjectID(selectedThread.projectID)
        } else {
            root.selectedProjectID = knownProjectID(root.selectedProjectID)
        }
        saveProjects()
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        recordNavigationTransition(from: previousLocation)
        pruneNavigationHistory()
        return true
    }
}
