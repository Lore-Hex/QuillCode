import Foundation
import QuillCodeCore
import QuillCodeTools
import QuillComputerUseKit

/// The SF Symbol that names a tool call by its TYPE — terminal / read / edit / search / … — for the
/// tool card's leading glyph. The card's circle stays TINTED by run status (blue/green/red) and the
/// trailing badge keeps the running/done/failed word, so status is never lost; this restores the
/// "type-icon + verb + target" scan line Codex/Claude-Code cards have (a scrolled transcript becomes
/// scannable by shape). Keyed on the raw tool id via the same `ToolDefinition.<x>.name` constants the
/// display-name builder uses, so the id set stays single-sourced. Unknown ids fall to a neutral tool.
enum WorkspaceToolGlyphBuilder {
    static func symbolName(for toolName: String) -> String {
        switch toolName {
        case ToolDefinition.shellRun.name:
            return "terminal"
        case ToolDefinition.fileRead.name:
            return "doc.text"
        case ToolDefinition.fileWrite.name:
            return "square.and.pencil"
        case ToolDefinition.fileList.name:
            return "folder"
        case ToolDefinition.fileSearch.name:
            return "magnifyingglass"
        case ToolDefinition.applyPatch.name:
            return "pencil"
        case ToolDefinition.gitDiff.name, ToolDefinition.gitPullRequestDiff.name:
            return "plus.forwardslash.minus"
        case ToolDefinition.gitCommit.name:
            return "checkmark.seal"
        case ToolDefinition.gitPush.name:
            return "arrow.up.circle"
        case ToolDefinition.gitPull.name, ToolDefinition.gitFetch.name:
            return "arrow.down.circle"
        case ToolDefinition.gitStatus.name,
             ToolDefinition.gitBranchList.name,
             ToolDefinition.gitBranchSwitch.name,
             ToolDefinition.gitStage.name,
             ToolDefinition.gitStageHunk.name,
             ToolDefinition.gitUnstageHunk.name,
             ToolDefinition.gitRestore.name,
             ToolDefinition.gitRestoreHunk.name,
             ToolDefinition.gitWorktreeList.name,
             ToolDefinition.gitWorktreeCreate.name,
             ToolDefinition.gitWorktreeCreateBranch.name,
             ToolDefinition.gitWorktreeOpen.name,
             ToolDefinition.gitWorktreeRemove.name,
             ToolDefinition.gitWorktreePrune.name:
            return "arrow.triangle.branch"
        case ToolDefinition.gitPullRequestList.name,
             ToolDefinition.gitPullRequestCreate.name,
             ToolDefinition.gitPullRequestView.name,
             ToolDefinition.gitPullRequestChecks.name,
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
             ToolDefinition.gitPullRequestMerge.name:
            return "arrow.triangle.pull"
        case ToolDefinition.browserOpen.name,
             ToolDefinition.browserInspect.name,
             ToolDefinition.browserClick.name,
             ToolDefinition.browserType.name,
             ToolDefinition.browserScript.name,
             ToolDefinition.webSearch.name,
             ToolDefinition.webFetch.name:
            return "globe"
        case ToolDefinition.computerScreenshot.name:
            return "camera"
        case ToolDefinition.computerClick.name:
            return "cursorarrow.click"
        case ToolDefinition.computerType.name, ToolDefinition.computerKey.name:
            return "keyboard"
        case ToolDefinition.computerScroll.name:
            return "arrow.up.arrow.down"
        case ToolDefinition.computerMove.name:
            return "cursorarrow.motionlines"
        case ToolDefinition.mcpCall.name,
             ToolDefinition.mcpReadResource.name,
             ToolDefinition.mcpGetPrompt.name,
             ToolDefinition.localPluginInstall.name:
            return "puzzlepiece.extension"
        case ToolDefinition.memoryRemember.name:
            return "brain"
        case ToolDefinition.planUpdate.name:
            return "checklist"
        case ToolDefinition.handoffUpdate.name:
            return "arrow.left.arrow.right"
        case ToolDefinition.subagentsRun.name, ToolDefinition.subagentsUpdate.name:
            return "person.2"
        case ToolDefinition.workflowRecordStart.name:
            return "record.circle"
        case ToolDefinition.workflowRecordStop.name:
            return "stop.circle"
        default:
            return "wrench.and.screwdriver"
        }
    }
}
