import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    /// Stashes the outgoing thread's draft and restores the incoming thread's
    /// draft when lifecycle changes reassign the selected thread.
    func applyThreadDraftSelection(to newID: UUID?, removing removed: UUID? = nil) {
        let outgoing = root.selectedThreadID
        if outgoing != newID {
            restoreComposerDraft(from: outgoing, to: newID)
        }
        if let removed {
            threadDrafts = ComposerDraftStore.cleared(removed, drafts: threadDrafts)
        }
    }

    /// Destroys the selected incognito thread when the user navigates away (new chat, thread or
    /// project selection): removes it from memory, finishes its runs, clears its draft, and prunes it
    /// from navigation history so Workspace Back can never resurrect the "never saved" conversation.
    /// Distills a destroyed ephemeral thread's provider-usage events (token counts, model id,
    /// timestamps — never message content) into a stub the spend-period ledger can keep counting.
    private static func spendReceiptStub(from thread: ChatThread) -> ChatThread? {
        let usageEvents = thread.events.filter { ModelTokenUsageEvent.usage(from: $0) != nil }
        guard !usageEvents.isEmpty else { return nil }
        return ChatThread(
            title: "Incognito spend receipt",
            model: thread.model,
            events: usageEvents,
            createdAt: thread.createdAt,
            updatedAt: thread.updatedAt
        )
    }

    @discardableResult
    func discardIncognitoThreadOnExit() -> Bool {
        guard let current = selectedThread, current.runtimeContext.isIncognito else { return false }
        // Spend must survive the destruction (limits would otherwise be resettable by cycling
        // incognito sessions); the receipt carries no conversation content.
        if let receipt = Self.spendReceiptStub(from: current) {
            discardedEphemeralSpendThreads.append(receipt)
        }
        root.threads.removeAll { $0.id == current.id }
        sessionStartHookCoordinator.remove(threadID: current.id)
        agentRuns.finish(threadID: current.id)
        // The registry entry above is bookkeeping; the OWNING send task lives in the desktop task
        // coordinator, which observes this callback to actually cancel provider/tool work.
        onEphemeralThreadDiscarded?(current.id)
        threadDrafts = ComposerDraftStore.cleared(current.id, drafts: threadDrafts)
        // The LIVE composer belongs to the discarded session too: unsent private text (and attached
        // images) must not stay visible under whatever gets selected next.
        composer.draft = ""
        composer.attachments = []
        navigationHistory.pruneEntries(withThreadID: current.id)
        // The workspace-scoped error surface (runtimeIssueSurface derives from lastError) must not
        // carry the private session's failures into the next chat — a run-failed card from an
        // incognito send otherwise lingers, provider error text included, in the new thread.
        setLastError(nil)
        if root.selectedThreadID == current.id {
            root.selectedThreadID = nil
        }
        return true
    }

    public func selectThread(_ id: UUID, recordsNavigation: Bool = true) {
        if id != root.selectedThreadID {
            _ = returnFromSideConversation()
            _ = discardIncognitoThreadOnExit()
        }
        guard let thread = root.threads.first(where: { $0.id == id }) else { return }
        let previousLocation = currentNavigationLocation
        // The user is leaving the current thread: persist its morning-triage return watermark to its
        // current tail so background growth on it surfaces as "unseen" on return (cross-session).
        // Only on an actual thread switch, mirroring the transcript tracker's leave transition.
        if let outgoing = root.selectedThreadID, outgoing != id {
            persistOutgoingReturnWatermark()
        }
        restoreComposerDraft(from: root.selectedThreadID, to: id)
        selectThreadRecord(id, projectID: thread.projectID)
        if recordsNavigation {
            recordNavigationTransition(from: previousLocation)
        }
        enforceManagedWorktreeRetention()
    }

    @discardableResult
    public func selectAdjacentSidebarThread(offset: Int) -> Bool {
        let items = filteredSidebarItems()
        guard !items.isEmpty, offset != 0 else { return false }
        let selectedIndex = root.selectedThreadID.flatMap { selectedID in
            items.firstIndex { $0.id == selectedID }
        }
        let targetIndex: Int
        if let selectedIndex {
            guard items.count > 1 else { return false }
            targetIndex = (selectedIndex + offset % items.count + items.count) % items.count
        } else {
            targetIndex = offset < 0 ? items.count - 1 : 0
        }
        selectThread(items[targetIndex].id)
        return true
    }

    @discardableResult
    func insertCreatedThread(
        _ thread: ChatThread,
        selectedProjectID: UUID?,
        saveThread: Bool,
        recordsNavigation: Bool = true,
        sessionStartSource: ProjectPluginSessionStartSource = .startup
    ) -> UUID {
        let previousLocation = currentNavigationLocation
        // Leaving the current thread for a newly created one (New Chat / fork / compact): persist its
        // return watermark, mirroring the harness's newChat() → markTranscriptSeen.
        if let outgoing = root.selectedThreadID, outgoing != thread.id {
            persistOutgoingReturnWatermark()
        }
        clearSidebarSelection()
        restoreComposerDraft(from: root.selectedThreadID, to: thread.id)
        root.threads.insert(thread, at: 0)
        sessionStartHookCoordinator.registerCreatedThread(thread.id, source: sessionStartSource)
        selectThreadRecord(thread.id, projectID: selectedProjectID)
        if saveThread {
            threadPersistence.save(thread)
        }
        if recordsNavigation {
            recordNavigationTransition(from: previousLocation)
        }
        enforceManagedWorktreeRetention()
        return thread.id
    }

    private func restoreComposerDraft(from outgoing: UUID?, to incoming: UUID?) {
        if let incoming {
            if let outgoing, outgoing != incoming {
                persistComposerDraft(composer.draft, for: outgoing)
                persistComposerAttachments(composer.attachments, for: outgoing)
            }
            let result = ComposerDraftStore.select(
                outgoing: outgoing,
                incoming: incoming,
                liveDraft: composer.draft,
                drafts: threadDrafts
            )
            threadDrafts = result.drafts
            composer.draft = result.restoredDraft.isEmpty
                ? persistedComposerDraft(for: incoming) ?? ""
                : result.restoredDraft
            composer.attachments = persistedComposerAttachments(for: incoming)
        } else if let outgoing {
            stashOutgoingThreadDraft(outgoing)
        }
    }

    private func stashOutgoingThreadDraft(_ outgoing: UUID) {
        let normalizedDraft = Self.normalizedComposerDraft(composer.draft)
        if normalizedDraft == nil {
            threadDrafts[outgoing] = nil
        } else {
            threadDrafts[outgoing] = composer.draft
        }
        persistComposerDraft(normalizedDraft, for: outgoing)
        composer.draft = ""
        persistComposerAttachments(composer.attachments, for: outgoing)
        composer.attachments = []
    }

    private func selectThreadRecord(_ id: UUID, projectID: UUID?) {
        root.selectedThreadID = id
        root.selectedProjectID = knownProjectID(projectID)
        syncTerminalSessionToSelectedProject()
        refreshFileMentionIndex()
        touchProject(root.selectedProjectID)
        saveProjects()
        refreshSelectedAgentRunPresentation()
        scheduleSelectedPullRequestReconciliation()
    }
}
