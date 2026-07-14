import Foundation
import QuillCodeCore

@MainActor
struct WorkspaceManagedWorktreeFinishCoordinator {
    let model: QuillCodeWorkspaceModel

    func finishSelectedThread() -> Bool {
        guard let plan = finishPlan() else { return false }

        if plan.requiresHandoff {
            let handoff = model.runToolCall(
                WorkspaceWorktreeToolCallPlanner.handoff(destination: plan.localRoot.path),
                workspaceRoot: plan.worktreeRoot,
                managedWorktreeRoot: plan.authorizedManagedRoot
            )
            guard handoff.ok else { return false }
            model.activateSelectedThreadWorktreeLocation(.local, destination: plan.localRoot)
        }

        guard FileManager.default.fileExists(atPath: plan.worktreeRoot.path) else {
            complete(plan: plan, removedWorktree: false)
            return true
        }

        let removal = model.runToolCall(
            WorkspaceWorktreeToolCallPlanner.remove(
                WorkspaceWorktreeRemoveRequest(path: plan.worktreeRoot.path, force: false)
            ),
            workspaceRoot: plan.localRoot,
            managedWorktreeRoot: plan.authorizedManagedRoot
        )
        guard removal.ok else {
            model.appendNotice(
                "Task changes are in Local, but the isolated worktree was preserved because Git could not remove it safely. Review the failed removal, then retry Finish cleanup."
            )
            return false
        }

        complete(plan: plan, removedWorktree: true)
        return true
    }

    private func finishPlan() -> FinishPlan? {
        guard !model.composer.isSending,
              !model.terminal.isRunning,
              let threadID = model.root.selectedThreadID,
              model.selectedThread?.isArchived == false,
              let project = model.selectedProject,
              !project.isRemote,
              let binding = model.selectedThread?.worktree,
              binding.branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let localRoot = URL(fileURLWithPath: project.path).standardizedFileURL
        let worktreeRoot = URL(fileURLWithPath: binding.path).standardizedFileURL
        guard binding.location == .local || binding.isResolvable else { return nil }
        return FinishPlan(
            threadID: threadID,
            localRoot: localRoot,
            worktreeRoot: worktreeRoot,
            authorizedManagedRoot: binding.managedRoot.map {
                URL(fileURLWithPath: $0).standardizedFileURL
            },
            requiresHandoff: binding.location == .worktree
        )
    }

    private func complete(plan: FinishPlan, removedWorktree: Bool) {
        model.clearWorktreeBinding(threadID: plan.threadID)
        model.terminal.currentDirectoryPath = plan.localRoot.path
        model.terminal.environmentOverrides = [:]
        model.terminal.removedEnvironmentKeys = []
        model.terminal.resetInputModes()
        model.refreshFileMentionIndex()
        model.appendNotice(
            removedWorktree
                ? "Finished this task in Local and removed its isolated worktree."
                : "Finished this task in Local; its already-missing worktree binding was cleared."
        )
        model.refreshTopBar()
    }
}

private extension WorkspaceManagedWorktreeFinishCoordinator {
    struct FinishPlan {
        var threadID: UUID
        var localRoot: URL
        var worktreeRoot: URL
        var authorizedManagedRoot: URL?
        var requiresHandoff: Bool
    }
}
