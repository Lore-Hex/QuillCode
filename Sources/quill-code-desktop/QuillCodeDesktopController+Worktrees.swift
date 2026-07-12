import QuillCodeApp

@MainActor
extension QuillCodeDesktopController {
    func createWorktree(_ request: WorkspaceWorktreeCreateRequest) {
        worktreeCoordinator.createWorktree(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func createWorktreeBranch(_ request: WorkspaceWorktreeCreateBranchRequest) {
        _ = model.createBranchHere(request)
        refresh()
    }

    func worktreeChoiceLoad() async -> WorkspaceWorktreeChoiceLoad {
        await worktreeCoordinator.worktreeChoiceLoad(model: model, fallbackWorkspaceRoot: workspaceRoot)
    }

    func worktreePrunePreview() async -> WorkspaceWorktreePrunePreview {
        await worktreeCoordinator.worktreePrunePreview(model: model, fallbackWorkspaceRoot: workspaceRoot)
    }

    func openWorktree(_ request: WorkspaceWorktreeOpenRequest) {
        worktreeCoordinator.openWorktree(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func removeWorktree(_ request: WorkspaceWorktreeRemoveRequest) {
        worktreeCoordinator.removeWorktree(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }

    func pruneWorktrees(_ request: WorkspaceWorktreePruneRequest) {
        worktreeCoordinator.pruneWorktrees(request, model: model, fallbackWorkspaceRoot: workspaceRoot)
        refresh()
    }
}
