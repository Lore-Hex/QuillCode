import Foundation
import QuillCodeCore

struct GitToolCallDispatcher: Sendable {
    let workspaceRoot: URL
    let git: GitToolExecutor

    static let definitions: [ToolDefinition] = [
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
        .gitPullRequestMerge,
        .gitWorktreeList,
        .gitWorktreeCreate,
        .gitWorktreeOpen,
        .gitWorktreeRemove
    ]

    private static let toolNames = Set(definitions.map(\.name))

    static func handles(_ toolName: String) -> Bool {
        toolNames.contains(toolName)
    }

    func execute(name: String, arguments args: ToolArguments) throws -> ToolResult {
        switch name {
        case ToolDefinition.gitStatus.name:
            return git.status(cwd: workspaceRoot)
        case ToolDefinition.gitDiff.name:
            return git.diff(cwd: workspaceRoot, staged: args.bool("staged") ?? false)
        case ToolDefinition.gitStage.name:
            return git.stage(cwd: workspaceRoot, path: try args.requiredString("path"))
        case ToolDefinition.gitRestore.name:
            return git.restore(
                cwd: workspaceRoot,
                path: try args.requiredString("path"),
                staged: args.bool("staged") ?? false
            )
        case ToolDefinition.gitStageHunk.name:
            return git.stageHunk(
                cwd: workspaceRoot,
                path: try args.requiredString("path"),
                patch: try args.requiredString("patch")
            )
        case ToolDefinition.gitRestoreHunk.name:
            return git.restoreHunk(
                cwd: workspaceRoot,
                path: try args.requiredString("path"),
                patch: try args.requiredString("patch")
            )
        case ToolDefinition.gitCommit.name:
            return git.commit(cwd: workspaceRoot, message: try args.requiredString("message"))
        case ToolDefinition.gitPush.name:
            return git.push(
                cwd: workspaceRoot,
                remote: args.string("remote"),
                branch: args.string("branch"),
                setUpstream: args.bool("setUpstream") ?? false
            )
        case ToolDefinition.gitPullRequestCreate.name:
            return git.createPullRequest(
                cwd: workspaceRoot,
                title: args.string("title"),
                body: args.string("body"),
                base: args.string("base"),
                head: args.string("head"),
                draft: args.bool("draft") ?? false,
                fill: args.bool("fill") ?? false
            )
        case ToolDefinition.gitPullRequestView.name:
            return git.viewPullRequest(cwd: workspaceRoot, selector: args.string("selector"))
        case ToolDefinition.gitPullRequestChecks.name:
            return git.pullRequestChecks(cwd: workspaceRoot, selector: args.string("selector"))
        case ToolDefinition.gitPullRequestDiff.name:
            return git.diffPullRequest(cwd: workspaceRoot, selector: args.string("selector"))
        case ToolDefinition.gitPullRequestCheckout.name:
            return git.checkoutPullRequest(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                branch: args.string("branch")
            )
        case ToolDefinition.gitPullRequestReviewers.name:
            return git.updatePullRequestReviewers(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                add: args.stringArray("add"),
                remove: args.stringArray("remove")
            )
        case ToolDefinition.gitPullRequestLabels.name:
            return git.updatePullRequestLabels(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                add: args.stringArray("add"),
                remove: args.stringArray("remove")
            )
        case ToolDefinition.gitPullRequestComment.name:
            return git.commentOnPullRequest(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                body: try args.requiredString("body")
            )
        case ToolDefinition.gitPullRequestReview.name:
            return git.reviewPullRequest(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                action: try args.requiredString("action"),
                body: args.string("body")
            )
        case ToolDefinition.gitPullRequestMerge.name:
            return git.mergePullRequest(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                method: args.string("method"),
                auto: args.bool("auto") ?? false,
                deleteBranch: args.bool("deleteBranch") ?? false
            )
        case ToolDefinition.gitWorktreeList.name:
            return git.listWorktrees(cwd: workspaceRoot)
        case ToolDefinition.gitWorktreeCreate.name:
            return git.createWorktree(
                cwd: workspaceRoot,
                path: try args.requiredString("path"),
                branch: args.string("branch"),
                base: args.string("base")
            )
        case ToolDefinition.gitWorktreeOpen.name:
            return git.openWorktree(
                cwd: workspaceRoot,
                path: try args.requiredString("path")
            )
        case ToolDefinition.gitWorktreeRemove.name:
            return git.removeWorktree(
                cwd: workspaceRoot,
                path: try args.requiredString("path"),
                force: args.bool("force") ?? false
            )
        default:
            return ToolResult(ok: false, error: "Unknown tool: \(name)")
        }
    }
}
