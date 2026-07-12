import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    /// Saves and removes only detached worktrees owned by QuillCode. Archive remains available when
    /// backup or cleanup fails; in that case the checkout is deliberately retained and the failure is
    /// surfaced instead of risking user work.
    func preserveDisposableWorktreeBeforeArchive(threadID: UUID) {
        guard let store = worktreeSnapshotStore,
              let threadIndex = root.threads.firstIndex(where: { $0.id == threadID }),
              !root.threads[threadIndex].isPinned,
              !agentRuns.isRunning(threadID),
              let binding = root.threads[threadIndex].worktree,
              binding.isDisposableManagedWorktree,
              binding.isResolvable,
              let projectRoot = localProjectRoot(for: root.threads[threadIndex])
        else { return }

        let previousReference = binding.snapshot
        do {
            let reference = try store.capture(threadID: threadID, binding: binding)
            var savedThread = root.threads[threadIndex]
            savedThread.worktree?.snapshot = reference
            WorkspaceThreadNoticeAppender.appendNotice(
                "Managed worktree saved before archive: \(reference.fileCount) local file\(reference.fileCount == 1 ? "" : "s"), \(reference.byteCount) bytes.",
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
        } catch {
            setLastError(
                "The task was archived, but its worktree was kept because it could not be saved and removed safely: "
                    + error.localizedDescription
            )
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
