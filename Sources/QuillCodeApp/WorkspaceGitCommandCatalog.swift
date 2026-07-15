import Foundation

enum WorkspaceGitCommandCatalog {
    static func commands(hasWorkspaceOrRemoteProject: Bool) -> [WorkspaceCommandSurface] {
        let gitCommands = [
            WorkspaceCommandSurface(
                id: "code-review",
                title: "Review changes with QuillCode",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "code review", "find bugs", "review changes", "review commit", "base branch"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-status",
                title: "Git status",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "status", "changes", "remote"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-diff",
                title: "Show diff",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "diff", "changes", "remote"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-fetch",
                title: "Fetch latest refs",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "fetch", "sync", "remote", "latest", "refs"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pull",
                title: "Pull latest changes",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "pull", "sync", "remote", "latest", "ff-only"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-branch-list",
                title: "List branches",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "branch", "branches", "switch", "remote"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-branch-switch",
                title: "Switch branch",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["git", "branch", "checkout", "switch", "create"],
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
