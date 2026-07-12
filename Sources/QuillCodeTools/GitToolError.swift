public enum GitToolError: Error, CustomStringConvertible {
    case emptyPath
    case emptyPatch
    case emptyCommitMessage
    case emptyPullRequestTitle
    case emptyPullRequestComment
    case emptyPullRequestReviewBody
    case emptyPullRequestReviewers
    case emptyPullRequestLabels
    case invalidPullRequestReviewCommentID(Int)
    case invalidPullRequestReviewThreadID(String)
    case invalidPullRequestReviewThreadAction(String)
    case invalidPullRequestReviewLine(Int)
    case invalidPullRequestReviewLineRange(startLine: Int, line: Int)
    case invalidPullRequestReviewSide(String)
    case invalidPullRequestReviewAction(String)
    case invalidPullRequestMergeMethod(String)
    case invalidPullRequestListState(String)
    case invalidPullRequestListLimit(Int)
    case invalidPullRequestLifecycleAction(String)
    case invalidPullRequestSelector(String)
    case invalidPullRequestReviewer(String)
    case invalidPullRequestLabel(String)
    case emptyBranch
    case invalidGitName(String)
    case branchStartPointRequiresCreate
    case noCurrentBranch
    case outsideWorkspace(String)
    case mainWorkspaceWorktreePath
    case unregisteredWorktree(String)
    case worktreeAlreadyOwnsBranch(String)
    case patchPathMismatch(String)
    case temporaryPatchFailed(String)

    public var description: String {
        switch self {
        case .emptyPath:
            return "Git path is required."
        case .emptyPatch:
            return "Git patch is empty."
        case .emptyCommitMessage:
            return "Git commit message is required."
        case .emptyPullRequestTitle:
            return "Git pull request title is required unless fill is enabled."
        case .emptyPullRequestComment:
            return "Git pull request comment body is required."
        case .emptyPullRequestReviewBody:
            return "Git pull request review body is required for comment and request_changes actions."
        case .emptyPullRequestReviewers:
            return "At least one GitHub pull request reviewer to add or remove is required."
        case .emptyPullRequestLabels:
            return "At least one GitHub pull request label to add or remove is required."
        case .invalidPullRequestReviewCommentID(let value):
            return "GitHub pull request review comment ID must be positive: \(value)"
        case .invalidPullRequestReviewThreadID(let value):
            return "GitHub pull request review thread ID is unsupported: \(value)"
        case .invalidPullRequestReviewThreadAction(let value):
            return "GitHub pull request review thread action is unsupported: \(value)"
        case .invalidPullRequestReviewLine(let value):
            return "GitHub pull request review line must be positive: \(value)"
        case .invalidPullRequestReviewLineRange(let startLine, let line):
            return "GitHub pull request review start line \(startLine) must be before or equal to line \(line)."
        case .invalidPullRequestReviewSide(let value):
            return "GitHub pull request review side is unsupported: \(value)"
        case .invalidPullRequestReviewAction(let value):
            return "GitHub pull request review action is unsupported: \(value)"
        case .invalidPullRequestMergeMethod(let value):
            return "GitHub pull request merge method is unsupported: \(value)"
        case .invalidPullRequestListState(let value):
            return "GitHub pull request list state is unsupported: \(value)"
        case .invalidPullRequestListLimit(let value):
            return "GitHub pull request list limit must be between 1 and 100: \(value)"
        case .invalidPullRequestLifecycleAction(let value):
            return "GitHub pull request lifecycle action is unsupported: \(value)"
        case .invalidPullRequestSelector(let value):
            return "GitHub pull request selector is unsupported: \(value)"
        case .invalidPullRequestReviewer(let value):
            return "GitHub pull request reviewer is unsupported: \(value)"
        case .invalidPullRequestLabel(let value):
            return "GitHub pull request label is unsupported: \(value)"
        case .emptyBranch:
            return "Git branch is required."
        case .invalidGitName(let value):
            return "Git remote or branch contains unsupported characters: \(value)"
        case .branchStartPointRequiresCreate:
            return "Git branch startPoint can only be used when create is true."
        case .noCurrentBranch:
            return "Git push needs a branch, but the current checkout has no branch."
        case .outsideWorkspace(let path):
            return "Git path is outside the workspace: \(path)"
        case .mainWorkspaceWorktreePath:
            return "Git worktree path cannot be the main workspace."
        case .unregisteredWorktree(let path):
            return "Git worktree is not registered: \(path)"
        case .worktreeAlreadyOwnsBranch(let branch):
            return "This worktree already owns branch \(branch). Create branch here is available only from detached HEAD."
        case .patchPathMismatch(let path):
            return "Git patch touches a different path than requested: \(path)"
        case .temporaryPatchFailed(let message):
            return "Failed to prepare git patch: \(message)"
        }
    }
}
