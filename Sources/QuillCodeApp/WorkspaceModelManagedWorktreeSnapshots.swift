import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    /// Saves and removes only detached worktrees owned by QuillCode. Archive remains available when
    /// backup or cleanup fails; in that case the checkout is deliberately retained and the failure is
    /// surfaced instead of risking user work.
    func preserveDisposableWorktreeBeforeArchive(threadID: UUID) {
        _ = preserveAndRemoveDisposableWorktree(threadID: threadID, reason: .archive)
    }

    @discardableResult
    public func enforceManagedWorktreeRetention() -> Int {
        guard worktreeSnapshotStore != nil, root.config.managedWorktrees.automaticCleanupEnabled else {
            return 0
        }
        let runningThreadIDs = Set(root.threads.lazy.filter { self.agentRuns.isRunning($0.id) }.map(\.id))
        let plan = ManagedWorktreeRetentionPlanner.plan(
            threads: root.threads,
            selectedThreadID: root.selectedThreadID,
            runningThreadIDs: runningThreadIDs,
            settings: root.config.managedWorktrees
        )
        guard plan.targetRemovalCount > 0 else { return 0 }

        var removed = 0
        for threadID in plan.candidateThreadIDs where removed < plan.targetRemovalCount {
            if preserveAndRemoveDisposableWorktree(threadID: threadID, reason: .retention) {
                removed += 1
            }
        }
        if removed > 0 {
            refreshTopBar(agentStatus: root.topBar.agentStatus)
        }
        return removed
    }

    @discardableResult
    private func preserveAndRemoveDisposableWorktree(
        threadID: UUID,
        reason: ManagedWorktreeRemovalReason
    ) -> Bool {
        guard let store = worktreeSnapshotStore,
              let threadIndex = root.threads.firstIndex(where: { $0.id == threadID }),
              !root.threads[threadIndex].isPinned,
              !agentRuns.isRunning(threadID),
              let binding = root.threads[threadIndex].worktree,
              binding.isDisposableManagedWorktree,
              binding.isResolvable,
              let projectRoot = localProjectRoot(for: root.threads[threadIndex])
        else { return false }

        let previousReference = binding.snapshot
        do {
            let authorizedRoot = binding.managedRoot.map(URL.init(fileURLWithPath:))
                ?? managedWorktreeRoot
            let reference = try store.capture(
                threadID: threadID,
                binding: binding,
                managedRoot: authorizedRoot
            )
            var savedThread = root.threads[threadIndex]
            savedThread.worktree?.snapshot = reference
            WorkspaceThreadNoticeAppender.appendNotice(
                reason.savedNotice(reference),
                to: &savedThread
            )
            try threadPersistence.saveOrThrow(savedThread)
            root.threads[threadIndex] = savedThread
            if let previousReference, previousReference.id != reference.id {
                try? store.delete(previousReference)
            }

            var capturedBinding = binding
            capturedBinding.snapshot = reference
            try store.removeIfUnchanged(
                threadID: threadID,
                reference: reference,
                binding: capturedBinding,
                projectRoot: projectRoot
            )
            return true
        } catch {
            setLastError(
                reason.preservationFailurePrefix
                    + error.localizedDescription
            )
            return false
        }
    }

    @discardableResult
    public func restoreManagedWorktree(threadID: UUID) -> Bool {
        guard !agentRuns.isRunning(threadID) else {
            setLastError("Stop this task before restoring its worktree.")
            return false
        }
        guard let store = worktreeSnapshotStore,
              let threadIndex = root.threads.firstIndex(where: { $0.id == threadID }),
              var binding = root.threads[threadIndex].worktree,
              let reference = binding.snapshot,
              binding.canRestoreSnapshot,
              let projectRoot = localProjectRoot(for: root.threads[threadIndex])
        else {
            setLastError("This task does not have a restorable worktree snapshot.")
            return false
        }

        do {
            let result = try store.restore(
                threadID: threadID,
                reference: reference,
                binding: binding,
                projectRoot: projectRoot
            )
            binding.snapshot = nil
            var restoredThread = root.threads[threadIndex]
            restoredThread.worktree = binding
            restoredThread.updatedAt = Date()
            WorkspaceThreadNoticeAppender.appendNotice(
                "Managed worktree restored at \(result.path) with \(result.restoredFileCount) local file\(result.restoredFileCount == 1 ? "" : "s").",
                to: &restoredThread
            )
            try threadPersistence.saveOrThrow(restoredThread)
            root.threads[threadIndex] = restoredThread
            do {
                try store.delete(reference)
            } catch {
                setLastError("The worktree was restored, but its old backup could not be removed: \(error.localizedDescription)")
            }
            syncTerminalSessionToSelectedProject()
            refreshProjectMetadata(restoredThread.projectID)
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        } catch {
            setLastError("The worktree could not be restored: \(error.localizedDescription)")
            return false
        }
    }

    func deleteWorktreeSnapshotIfPresent(in thread: ChatThread) {
        guard let reference = thread.worktree?.snapshot else { return }
        do {
            try worktreeSnapshotStore?.delete(reference)
        } catch {
            setLastError("The chat was deleted, but its worktree backup could not be removed: \(error.localizedDescription)")
        }
    }

    private func localProjectRoot(for thread: ChatThread) -> URL? {
        guard let projectID = thread.projectID,
              let project = root.projects.first(where: { $0.id == projectID }),
              !project.isRemote else {
            return nil
        }
        return URL(fileURLWithPath: project.connection.path).standardizedFileURL
    }
}

private enum ManagedWorktreeRemovalReason {
    case archive
    case retention

    func savedNotice(_ reference: WorktreeSnapshotReference) -> String {
        let files = "\(reference.fileCount) local file\(reference.fileCount == 1 ? "" : "s")"
        switch self {
        case .archive:
            return "Managed worktree saved before archive: \(files), \(reference.byteCount) bytes."
        case .retention:
            return "Managed worktree saved by automatic cleanup: \(files), \(reference.byteCount) bytes."
        }
    }

    var preservationFailurePrefix: String {
        switch self {
        case .archive:
            return "The task was archived, but its worktree was kept because it could not be saved and removed safely: "
        case .retention:
            return "Automatic cleanup kept a managed worktree because it could not be saved and removed safely: "
        }
    }
}
