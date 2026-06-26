import Foundation
import QuillCodeApp

@MainActor
struct QuillCodeDesktopWorktreeCoordinator {
    func createWorktree(
        _ request: WorkspaceWorktreeCreateRequest,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        let root = workspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        model.createWorktree(request, workspaceRoot: root)
    }

    func worktreeChoiceLoad(
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) async -> WorkspaceWorktreeChoiceLoad {
        let root = workspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        let request = model.worktreeChoiceLoadRequest(
            workspaceRoot: root
        )
        return await Task.detached(priority: .userInitiated) {
            request.load()
        }.value
    }

    func worktreePrunePreview(
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) async -> WorkspaceWorktreePrunePreview {
        let root = workspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        let request = model.worktreePrunePreviewLoadRequest(
            workspaceRoot: root
        )
        return await Task.detached(priority: .userInitiated) {
            request.load()
        }.value
    }

    func openWorktree(
        _ request: WorkspaceWorktreeOpenRequest,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        let root = workspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        model.openWorktree(request, workspaceRoot: root)
    }

    func removeWorktree(
        _ request: WorkspaceWorktreeRemoveRequest,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        let root = workspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        model.removeWorktree(request, workspaceRoot: root)
    }

    func pruneWorktrees(
        _ request: WorkspaceWorktreePruneRequest,
        model: QuillCodeWorkspaceModel,
        fallbackWorkspaceRoot: URL
    ) {
        let root = workspaceRoot(for: model, fallback: fallbackWorkspaceRoot)
        model.pruneWorktrees(request, workspaceRoot: root)
    }

    private func workspaceRoot(
        for model: QuillCodeWorkspaceModel,
        fallback workspaceRoot: URL
    ) -> URL {
        model.activeWorkspaceRoot ?? workspaceRoot
    }
}
