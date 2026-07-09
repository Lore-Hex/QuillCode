import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

enum WorkspaceToolDisplayNameBuilder {
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
