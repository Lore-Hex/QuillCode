import Foundation
import QuillCodeCore

struct GitToolCallDispatcher: Sendable {
    let workspaceRoot: URL
    let git: GitToolExecutor

    static let definitions: [ToolDefinition] = [
        .gitStatus,
        .gitDiff,
        .gitFetch,
        .gitPull,
        .gitBranchList,
        .gitBranchSwitch,
        .gitStage,
        .gitRestore,
        .gitStageHunk,
        .gitRestoreHunk,
        .gitCommit,
        .gitPush,
        .gitPullRequestList,
        .gitPullRequestCreate,
        .gitPullRequestView,
        .gitPullRequestChecks,
        .gitPullRequestDiff,
        .gitPullRequestCheckout,
        .gitPullRequestReviewers,
        .gitPullRequestLabels,
        .gitPullRequestComment,
        .gitPullRequestLifecycle,
        .gitPullRequestReview,
        .gitPullRequestReviewComment,
        .gitPullRequestReviewReply,
        .gitPullRequestReviewThreads,
        .gitPullRequestReviewThread,
        .gitPullRequestMerge,
        .gitWorktreeList,
        .gitWorktreeCreate,
        .gitWorktreeOpen,
        .gitWorktreeHandoff,
        .gitWorktreeCreateBranch,
        .gitWorktreeRemove,
        .gitWorktreePrune
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
        case ToolDefinition.gitFetch.name:
            return git.fetch(
                cwd: workspaceRoot,
                remote: args.string("remote"),
                prune: args.bool("prune") ?? false
            )
        case ToolDefinition.gitPull.name:
            return git.pull(
                cwd: workspaceRoot,
                remote: args.string("remote"),
                branch: args.string("branch"),
                ffOnly: args.bool("ffOnly") ?? true
            )
        case ToolDefinition.gitBranchList.name:
            return git.listBranches(cwd: workspaceRoot, includeRemote: args.bool("includeRemote") ?? true)
        case ToolDefinition.gitBranchSwitch.name:
            return git.switchBranch(
                cwd: workspaceRoot,
                branch: try args.requiredString("branch"),
                create: args.bool("create") ?? false,
                startPoint: args.string("startPoint")
            )
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
        case ToolDefinition.gitPullRequestList.name:
            return git.listPullRequests(
                cwd: workspaceRoot,
                state: args.string("state"),
                limit: args.int("limit")
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
        case ToolDefinition.gitPullRequestLifecycle.name:
            return git.updatePullRequestLifecycle(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                action: try args.requiredString("action")
            )
        case ToolDefinition.gitPullRequestReview.name:
            return git.reviewPullRequest(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                action: try args.requiredString("action"),
                body: args.string("body")
            )
        case ToolDefinition.gitPullRequestReviewComment.name:
            return git.commentOnPullRequestLine(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                path: try args.requiredString("path"),
                line: try args.requiredInt("line"),
                side: args.string("side"),
                body: try args.requiredString("body"),
                startLine: args.int("startLine"),
                startSide: args.string("startSide")
            )
        case ToolDefinition.gitPullRequestReviewReply.name:
            return git.replyToPullRequestReviewComment(
                cwd: workspaceRoot,
                selector: args.string("selector"),
                commentID: try args.requiredInt("commentId"),
                body: try args.requiredString("body")
            )
        case ToolDefinition.gitPullRequestReviewThreads.name:
            return git.listPullRequestReviewThreads(
                cwd: workspaceRoot,
                selector: args.string("selector")
            )
        case ToolDefinition.gitPullRequestReviewThread.name:
            return git.updatePullRequestReviewThread(
                cwd: workspaceRoot,
                threadID: try args.requiredString("threadId"),
                action: try args.requiredString("action")
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
                base: args.string("base"),
                managed: args.bool("managed") ?? false
            )
        case ToolDefinition.gitWorktreeOpen.name:
            return git.openWorktree(cwd: workspaceRoot, path: try args.requiredString("path"))
        case ToolDefinition.gitWorktreeHandoff.name:
            return git.handoffWorktree(
                cwd: workspaceRoot,
                destination: try args.requiredString("destination")
            )
        case ToolDefinition.gitWorktreeCreateBranch.name:
            return git.createWorktreeBranch(
                cwd: workspaceRoot,
                branch: try args.requiredString("branch")
            )
        case ToolDefinition.gitWorktreeRemove.name:
            return git.removeWorktree(
                cwd: workspaceRoot,
                path: try args.requiredString("path"),
                force: args.bool("force") ?? false
            )
        case ToolDefinition.gitWorktreePrune.name:
            return git.pruneWorktrees(
                cwd: workspaceRoot,
                dryRun: args.bool("dryRun") ?? false,
                verbose: args.bool("verbose") ?? false
            )
        default:
            return ToolResult(ok: false, error: "Unknown tool: \(name)")
        }
    }
}
