import QuillCodeCore

public extension ToolDefinition {
    static let gitStatus = ToolDefinition(
        name: "host.git.status",
        description: "Show git status for the project.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .local,
        risk: .read
    )

    static let gitDiff = ToolDefinition(
        name: "host.git.diff",
        description: "Show git diff for the project.",
        parametersJSON: #"{"type":"object","properties":{"staged":{"type":"boolean"}}}"#,
        host: .local,
        risk: .read
    )

    static let gitStage = ToolDefinition(
        name: "host.git.stage",
        description: "Stage one file path inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .append
    )

    static let gitRestore = ToolDefinition(
        name: "host.git.restore",
        description: "Restore one file path inside the project from git.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"staged":{"type":"boolean"}},"required":["path"]}"#,
        host: .local,
        risk: .destructive
    )

    static let gitStageHunk = ToolDefinition(
        name: "host.git.stage_hunk",
        description: "Stage one selected git diff hunk inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"patch":{"type":"string"}},"required":["path","patch"]}"#,
        host: .local,
        risk: .append
    )

    static let gitRestoreHunk = ToolDefinition(
        name: "host.git.restore_hunk",
        description: "Restore one selected git diff hunk inside the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"patch":{"type":"string"}},"required":["path","patch"]}"#,
        host: .local,
        risk: .destructive
    )

    static let gitCommit = ToolDefinition(
        name: "host.git.commit",
        description: "Create a git commit from already staged project changes.",
        parametersJSON: #"{"type":"object","properties":{"message":{"type":"string"}},"required":["message"]}"#,
        host: .local,
        risk: .append
    )

    static let gitPush = ToolDefinition(
        name: "host.git.push",
        description: "Push a project branch to a named git remote. Defaults to remote origin and the current branch.",
        parametersJSON: #"{"type":"object","properties":{"remote":{"type":"string"},"branch":{"type":"string"},"setUpstream":{"type":"boolean"}}}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestCreate = ToolDefinition(
        name: "host.git.pr.create",
        description: "Create a GitHub pull request for the current project branch using GitHub CLI.",
        parametersJSON: #"{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"},"base":{"type":"string"},"head":{"type":"string"},"draft":{"type":"boolean"},"fill":{"type":"boolean"}}}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestView = ToolDefinition(
        name: "host.git.pr.view",
        description: "View the current or selected GitHub pull request, including comments, using GitHub CLI. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."}}}"#,
        host: .local,
        risk: .read
    )

    static let gitPullRequestChecks = ToolDefinition(
        name: "host.git.pr.checks",
        description: "Show CI/check status for the current or selected GitHub pull request using GitHub CLI. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."}}}"#,
        host: .local,
        risk: .read
    )

    static let gitPullRequestDiff = ToolDefinition(
        name: "host.git.pr.diff",
        description: "Show the unified diff for the current or selected GitHub pull request using GitHub CLI. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."}}}"#,
        host: .local,
        risk: .read
    )

    static let gitPullRequestCheckout = ToolDefinition(
        name: "host.git.pr.checkout",
        description: "Check out the current or selected GitHub pull request branch using GitHub CLI. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."},"branch":{"type":"string","description":"Optional local branch name to use for the checkout."}}}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestReviewers = ToolDefinition(
        name: "host.git.pr.reviewers",
        description: "Request or remove reviewers on the current or selected GitHub pull request using GitHub CLI. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."},"add":{"type":"array","items":{"type":"string"},"description":"Reviewer logins or org/team slugs to request."},"remove":{"type":"array","items":{"type":"string"},"description":"Reviewer logins or org/team slugs to remove."}}}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestLabels = ToolDefinition(
        name: "host.git.pr.labels",
        description: "Add or remove labels on the current or selected GitHub pull request using GitHub CLI. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."},"add":{"type":"array","items":{"type":"string"},"description":"Labels to add."},"remove":{"type":"array","items":{"type":"string"},"description":"Labels to remove."}}}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestComment = ToolDefinition(
        name: "host.git.pr.comment",
        description: "Add a top-level comment to the current or selected GitHub pull request using GitHub CLI. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."},"body":{"type":"string","description":"Comment body to post."}},"required":["body"]}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestReview = ToolDefinition(
        name: "host.git.pr.review",
        description: "Submit a GitHub pull request review using GitHub CLI. Action must be approve, comment, or request_changes. Optional selector may be a PR number, URL, or branch.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."},"action":{"type":"string","enum":["approve","comment","request_changes"]},"body":{"type":"string","description":"Review body. Required for comment and request_changes."}},"required":["action"]}"#,
        host: .local,
        risk: .append
    )

    static let gitPullRequestMerge = ToolDefinition(
        name: "host.git.pr.merge",
        description: "Merge or enable auto-merge for the current or selected GitHub pull request using GitHub CLI. Method must be squash, merge, or rebase.",
        parametersJSON: #"{"type":"object","properties":{"selector":{"type":"string","description":"Optional pull request number, URL, or branch. Omit to use the current branch."},"method":{"type":"string","enum":["squash","merge","rebase"],"description":"Merge method. Defaults to squash."},"auto":{"type":"boolean","description":"Use GitHub auto-merge when checks are still pending."},"deleteBranch":{"type":"boolean","description":"Delete the pull request branch after merge when supported."}}}"#,
        host: .local,
        risk: .destructive
    )

    static let gitWorktreeList = ToolDefinition(
        name: "host.git.worktree.list",
        description: "List git worktrees for the project.",
        parametersJSON: #"{"type":"object","properties":{}}"#,
        host: .local,
        risk: .read
    )

    static let gitWorktreeCreate = ToolDefinition(
        name: "host.git.worktree.create",
        description: "Create a sibling git worktree for the project, optionally with a new branch and base ref.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"branch":{"type":"string"},"base":{"type":"string"}},"required":["path"]}"#,
        host: .local,
        risk: .append
    )

    static let gitWorktreeRemove = ToolDefinition(
        name: "host.git.worktree.remove",
        description: "Remove a registered sibling git worktree for the project.",
        parametersJSON: #"{"type":"object","properties":{"path":{"type":"string"},"force":{"type":"boolean"}},"required":["path"]}"#,
        host: .local,
        risk: .destructive
    )
}
