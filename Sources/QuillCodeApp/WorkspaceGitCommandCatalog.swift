import Foundation

enum WorkspaceGitCommandCatalog {
    static func commands(hasWorkspaceOrRemoteProject: Bool) -> [WorkspaceCommandSurface] {
        [
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
            WorkspaceCommandSurface(
                id: "git-pr-create",
                title: "Create pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "pull request", "review"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-view",
                title: "View pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "view", "comments", "review"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-checks",
                title: "Pull request checks",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "checks", "ci", "status"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-diff",
                title: "Pull request diff",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "pr diff", "pull request diff", "diff", "review", "changes"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-checkout",
                title: "Checkout pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "checkout", "switch", "branch"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-reviewers",
                title: "Request pull request reviewers",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "reviewer", "reviewers", "request review"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-comment",
                title: "Comment on pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "comment", "comment pull", "reply", "discussion"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-review",
                title: "Review pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "review", "approve", "approve pr", "request changes"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-review-comment",
                title: "Comment on pull request line",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "review", "inline", "line comment", "review comment"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-review-reply",
                title: "Reply to pull request line comment",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "review", "reply", "inline reply", "review comment reply"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-review-threads",
                title: "List pull request review threads",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "review", "thread", "threads", "unresolved", "ids", "browse"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-review-thread",
                title: "Resolve pull request review thread",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "review", "thread", "resolve", "unresolve"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-labels",
                title: "Label pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "label", "labels", "triage"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
            WorkspaceCommandSurface(
                id: "git-pr-merge",
                title: "Merge pull request",
                category: WorkspaceCommandPalette.gitCategory,
                keywords: ["github", "pr", "merge", "automerge", "merge train"],
                isEnabled: hasWorkspaceOrRemoteProject
            ),
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
    }
}
