import Foundation

enum WorkspaceGitCommandCatalog {
    static func commands(hasWorkspaceOrRemoteProject: Bool) -> [WorkspaceCommandSurface] {
        let gitCommands = [
            WorkspaceCommandSurface(
                id: "git-status",
                title: "Git status",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "status", "changes", "remote"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-diff",
                title: "Review diff",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "diff", "review", "changes", "remote"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
        ]

        let worktreeCommands = [
            WorkspaceCommandSurface(
                id: "git-worktree-list",
                title: "List worktrees",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-create",
                title: "Create worktree",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-open",
                title: "Open worktree",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace", "switch"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-remove",
                title: "Remove worktree",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace", "delete"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-worktree-prune",
                title: "Prune stale worktrees",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["branch", "git", "workspace", "cleanup", "prune"],
                isEnabled: hasWorkspaceOrRemoteProject
            )
        ]

        return gitCommands
            + WorkspacePullRequestCommandCatalog.commands(isEnabled: hasWorkspaceOrRemoteProject)
            + worktreeCommands
    }
}
