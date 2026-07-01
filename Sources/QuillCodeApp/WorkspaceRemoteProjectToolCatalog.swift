import Foundation
import QuillCodeCore

enum WorkspaceRemoteProjectToolCatalog {
    static let toolDefinitions: [ToolDefinition] = [
        .shellRun,
        .fileRead,
        .fileList,
        .fileWrite,
        .applyPatch
    ] + gitToolDefinitions

    static let gitToolNames = Set(gitToolDefinitions.map(\.name))

    private static let gitToolDefinitions: [ToolDefinition] = [
        .gitStatus,
        .gitDiff,
        .gitStage,
        .gitRestore,
        .gitStageHunk,
        .gitRestoreHunk,
        .gitCommit,
        .gitPush,
        .gitPullRequestCreate,
        .gitPullRequestView,
        .gitPullRequestChecks,
        .gitPullRequestDiff,
        .gitPullRequestCheckout,
        .gitPullRequestReviewers,
        .gitPullRequestLabels,
        .gitPullRequestComment,
        .gitPullRequestReview,
        .gitPullRequestReviewComment,
        .gitPullRequestReviewReply,
        .gitPullRequestReviewThreads,
        .gitPullRequestReviewThread,
        .gitPullRequestMerge,
        .gitWorktreeList,
        .gitWorktreeCreate,
        .gitWorktreeOpen,
        .gitWorktreeRemove,
        .gitWorktreePrune
    ]
}
