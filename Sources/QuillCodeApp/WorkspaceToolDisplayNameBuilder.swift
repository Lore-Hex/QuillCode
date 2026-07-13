import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

enum WorkspaceToolDisplayNameBuilder {
    static let knownToolNames: [String] = [
        ToolDefinition.shellRun.name,
        ToolDefinition.fileRead.name,
        ToolDefinition.fileWrite.name,
        ToolDefinition.fileList.name,
        ToolDefinition.fileSearch.name,
        ToolDefinition.applyPatch.name,
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitFetch.name,
        ToolDefinition.gitPull.name,
        ToolDefinition.gitBranchList.name,
        ToolDefinition.gitBranchSwitch.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitStageHunk.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitRestoreHunk.name,
        ToolDefinition.gitCommit.name,
        ToolDefinition.gitPush.name,
        ToolDefinition.gitPullRequestList.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestReviewThreads.name,
        ToolDefinition.gitPullRequestReviewThread.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestLifecycle.name,
        ToolDefinition.gitPullRequestMerge.name,
        ToolDefinition.gitWorktreeList.name,
        ToolDefinition.gitWorktreeCreate.name,
        ToolDefinition.gitWorktreeCreateBranch.name,
        ToolDefinition.gitWorktreeOpen.name,
        ToolDefinition.gitWorktreeRemove.name,
        ToolDefinition.gitWorktreePrune.name,
        ToolDefinition.browserOpen.name,
        ToolDefinition.browserInspect.name,
        ToolDefinition.browserClick.name,
        ToolDefinition.browserType.name,
        ToolDefinition.browserScript.name,
        ToolDefinition.webSearch.name,
        ToolDefinition.webFetch.name,
        ToolDefinition.computerScreenshot.name,
        ToolDefinition.computerClick.name,
        ToolDefinition.computerType.name,
        ToolDefinition.computerScroll.name,
        ToolDefinition.computerMove.name,
        ToolDefinition.computerKey.name,
        ToolDefinition.mcpCall.name,
        ToolDefinition.mcpReadResource.name,
        ToolDefinition.mcpGetPrompt.name,
        ToolDefinition.localPluginInstall.name,
        ToolDefinition.memoryRemember.name,
        ToolDefinition.planUpdate.name,
        ToolDefinition.handoffUpdate.name,
        ToolDefinition.subagentsUpdate.name
    ]

    static func displayName(for toolName: String) -> String {
        switch toolName {
        case ToolDefinition.shellRun.name:
            return "Shell command"
        case ToolDefinition.fileRead.name:
            return "Read file"
        case ToolDefinition.fileWrite.name:
            return "Write file"
        case ToolDefinition.fileList.name:
            return "List files"
        case ToolDefinition.fileSearch.name:
            return "Search files"
        case ToolDefinition.applyPatch.name:
            return "Apply patch"
        case ToolDefinition.gitStatus.name:
            return "Git status"
        case ToolDefinition.gitDiff.name:
            return "Git diff"
        case ToolDefinition.gitFetch.name:
            return "Git fetch"
        case ToolDefinition.gitPull.name:
            return "Git pull"
        case ToolDefinition.gitBranchList.name:
            return "Git branches"
        case ToolDefinition.gitBranchSwitch.name:
            return "Switch branch"
        case ToolDefinition.gitStage.name, ToolDefinition.gitStageHunk.name:
            return "Stage changes"
        case ToolDefinition.gitRestore.name, ToolDefinition.gitRestoreHunk.name:
            return "Restore changes"
        case ToolDefinition.gitCommit.name:
            return "Git commit"
        case ToolDefinition.gitPush.name:
            return "Git push"
        case ToolDefinition.gitPullRequestList.name:
            return "List pull requests"
        case ToolDefinition.gitPullRequestCreate.name:
            return "Create pull request"
        case ToolDefinition.gitPullRequestView.name:
            return "View pull request"
        case ToolDefinition.gitPullRequestChecks.name:
            return "Pull request checks"
        case ToolDefinition.gitPullRequestDiff.name:
            return "Pull request diff"
        case ToolDefinition.gitPullRequestCheckout.name:
            return "Checkout pull request"
        case ToolDefinition.gitPullRequestComment.name:
            return "Pull request comment"
        case ToolDefinition.gitPullRequestReview.name:
            return "Pull request review"
        case ToolDefinition.gitPullRequestReviewComment.name:
            return "Review comment"
        case ToolDefinition.gitPullRequestReviewReply.name:
            return "Review reply"
        case ToolDefinition.gitPullRequestReviewThreads.name:
            return "Review threads"
        case ToolDefinition.gitPullRequestReviewThread.name:
            return "Review thread"
        case ToolDefinition.gitPullRequestReviewers.name:
            return "Pull request reviewers"
        case ToolDefinition.gitPullRequestLabels.name:
            return "Pull request labels"
        case ToolDefinition.gitPullRequestLifecycle.name:
            return "Pull request lifecycle"
        case ToolDefinition.gitPullRequestMerge.name:
            return "Merge pull request"
        case ToolDefinition.gitWorktreeList.name:
            return "List worktrees"
        case ToolDefinition.gitWorktreeCreate.name:
            return "Create worktree"
        case ToolDefinition.gitWorktreeCreateBranch.name:
            return "Create branch here"
        case ToolDefinition.gitWorktreeOpen.name:
            return "Open worktree"
        case ToolDefinition.gitWorktreeRemove.name:
            return "Remove worktree"
        case ToolDefinition.gitWorktreePrune.name:
            return "Prune worktrees"
        case ToolDefinition.browserOpen.name:
            return "Open browser"
        case ToolDefinition.browserInspect.name:
            return "Inspect browser"
        case ToolDefinition.browserClick.name:
            return "Browser click"
        case ToolDefinition.browserType.name:
            return "Browser type"
        case ToolDefinition.browserScript.name:
            return "Browser script"
        case ToolDefinition.webSearch.name:
            return "Web search"
        case ToolDefinition.webFetch.name:
            return "Web fetch"
        case ToolDefinition.computerScreenshot.name:
            return "Screenshot"
        case ToolDefinition.computerClick.name:
            return "Computer click"
        case ToolDefinition.computerType.name:
            return "Computer type"
        case ToolDefinition.computerScroll.name:
            return "Computer scroll"
        case ToolDefinition.computerMove.name:
            return "Move pointer"
        case ToolDefinition.computerKey.name:
            return "Keyboard shortcut"
        case ToolDefinition.mcpCall.name:
            return "MCP tool"
        case ToolDefinition.mcpReadResource.name:
            return "MCP resource"
        case ToolDefinition.mcpGetPrompt.name:
            return "MCP prompt"
        case ToolDefinition.localPluginInstall.name:
            return "Install plugin"
        case ToolDefinition.memoryRemember.name:
            return "Save memory"
        case ToolDefinition.planUpdate.name:
            return "Update plan"
        case ToolDefinition.handoffUpdate.name:
            return "Update handoff"
        case ToolDefinition.subagentsUpdate.name:
            return "Update subagents"
        default:
            return toolName
        }
    }
}
