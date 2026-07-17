import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func togglePinSelectedThread() {
        withSelectedThreadID(togglePinThread)
    }

    public func archiveSelectedThread() {
        withSelectedThreadID { _ = archiveThread($0) }
    }

    @discardableResult
    public func renameThread(_ id: UUID, to title: String) -> Bool {
        // A typed /rename bypasses palette enablement. Ephemeral titles must stay fixed: the title
        // reaches desktop notifications (persisted by OS notification history), and "Confidential" /
        // "Side: …" is also what keeps those surfaces content-free.
        if root.threads.first(where: { $0.id == id })?.runtimeContext.isEphemeral == true {
            setLastError("Confidential and side conversations can't be renamed.")
            return false
        }
        return updateAndSaveThread { threads in
            WorkspaceThreadLifecycleEngine.renameThread(id, to: title, threads: &threads)
        } != nil
    }

    public func togglePinThread(_ id: UUID) {
        let changed = updateAndSaveThread { threads in
            WorkspaceThreadLifecycleEngine.togglePinThread(id, threads: &threads)
        }
        if changed?.isPinned == false {
            enforceManagedWorktreeRetention()
        }
    }

    @discardableResult
    public func setPinThread(_ id: UUID, isPinned: Bool) -> Bool {
        let changed = updateAndSaveThread { threads in
            WorkspaceThreadLifecycleEngine.setPinThread(id, isPinned: isPinned, threads: &threads)
        }
        if changed != nil, !isPinned {
            enforceManagedWorktreeRetention()
        }
        return changed != nil
    }

    @discardableResult
    public func archiveThread(_ id: UUID) -> Bool {
        guard let target = root.threads.first(where: { $0.id == id && !$0.isArchived }) else {
            return false
        }
        // Archiving persists the thread and keeps it selectable from History — the opposite of an
        // ephemeral thread's contract. Typed /archive bypasses palette enablement, so refuse here.
        if target.runtimeContext.isEphemeral {
            setLastError("Confidential and side conversations can't be archived: they are never saved.")
            return false
        }
        preserveDisposableWorktreeBeforeArchive(threadID: id)
        return applyNavigationLifecycleChange {
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
        return applyNavigationLifecycleChange {
            guard let result = updateThreadLifecycle({
                WorkspaceThreadLifecycleEngine.unarchiveThread(id, threads: &$0)
            }) else { return false }

            // Unarchive selects the restored thread directly (not via selectThread), so the outgoing
            // confidential discard must run here too — otherwise Workspace Back could resurrect it.
            if root.selectedThreadID != id {
                _ = discardConfidentialThreadOnExit()
            }
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
        guard !agentRuns.isRunning(id) else {
            setLastError("Stop this chat before deleting it.")
            return false
        }
        // Typed /delete bypasses the discard-on-exit helper; keep the ephemeral spend receipt so a
        // deleted confidential session's usage still counts against the period limits, and clear the
        // workspace-scoped error so a private run's failure doesn't render as a runtime-issue card
        // in the next durable chat.
        if let target = root.threads.first(where: { $0.id == id }) {
            retainEphemeralSpendReceipt(for: target)
            if target.runtimeContext.isEphemeral && root.selectedThreadID == id {
                setLastError(nil)
            }
        }
        return applyNavigationLifecycleChange {
            guard let result = updateThreadLifecycle({ threads in
                WorkspaceThreadLifecycleEngine.deleteThread(
                    id,
                    threads: &threads,
                    selectedThreadID: root.selectedThreadID
                )
            }) else { return false }

            threadPersistence.delete(id)
            sessionStartHookCoordinator.remove(threadID: id)
            let subagentAttachments = removeSubagentArtifacts(for: result.removedThread)
            deleteWorktreeSnapshotIfPresent(in: result.removedThread)
            applyLifecycleSelection(result.selectedThreadID, removing: id)
            removeManagedImagesIfUnreferenced(
                Self.allImageAttachmentsForCleanup(in: result.removedThread) + subagentAttachments
            )
            syncSelectedProjectAfterDelete()
            saveProjects()
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            pruneNavigationHistory()
            return true
        }
    }

    @discardableResult
    public func clearThread(_ id: UUID) -> Bool {
        guard !agentRuns.isRunning(id) else {
            setLastError("Stop this chat before clearing it.")
            return false
        }
        let originalThread = root.threads.first(where: { $0.id == id })
        // /clear wipes the transcript (and its usage events); keep the ephemeral spend receipt first.
        if let originalThread {
            retainEphemeralSpendReceipt(for: originalThread)
            // Match /delete: an ephemeral thread stays put after /clear, so its private run's failure
            // would otherwise linger as a runtime-issue card. Clear the workspace-scoped error too.
            if originalThread.runtimeContext.isEphemeral && root.selectedThreadID == id {
                setLastError(nil)
            }
        }
        let attachments = originalThread.map(Self.allImageAttachmentsForCleanup) ?? []
        guard let result = updateThreadLifecycle({
            WorkspaceThreadLifecycleEngine.clearThread(id, threads: &$0)
        }) else {
            return false
        }

        clearComposerDraft(for: id)
        clearComposerAttachments(for: id)
        persistChangedThread(result.changedThread)
        sessionStartHookCoordinator.reset(threadID: id, source: .clear)
        let subagentAttachments = originalThread.map(removeSubagentArtifacts) ?? []
        removeManagedImagesIfUnreferenced(attachments + subagentAttachments)
        return true
    }

    private static func allImageAttachmentsForCleanup(in thread: ChatThread) -> [ChatAttachment] {
        thread.composerAttachments
            + thread.followUpQueue.flatMap(\.attachments)
            + thread.messages.flatMap(\.attachments)
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
