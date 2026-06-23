import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteGitToolRequest: Sendable, Hashable {
    var command: String
    var artifacts: [String]
    var extractsPullRequestURLs: Bool
}

enum WorkspaceRemoteGitToolRequestPlanner {
    static let pullRequestURLToolNames: Set<String> = [
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestMerge.name
    ]

    static func request(
        for call: ToolCall,
        connection: ProjectConnection
    ) throws -> WorkspaceRemoteGitToolRequest {
        let args = try ToolArguments(call.argumentsJSON)
        var artifacts: [String] = []
        let command: String

        switch call.name {
        case ToolDefinition.gitStatus.name:
            command = "git status --short --branch"
        case ToolDefinition.gitDiff.name:
            command = args.bool("staged") == true ? "git diff --staged" : "git diff"
        case ToolDefinition.gitStage.name:
            let path = try WorkspaceRemoteProjectPath.relativePath(try args.requiredString("path"))
            command = "git add -- \(shellSingleQuoted(path))"
        case ToolDefinition.gitRestore.name:
            let path = try WorkspaceRemoteProjectPath.relativePath(try args.requiredString("path"))
            let stagedFlag = args.bool("staged") == true ? " --staged" : ""
            command = "git restore\(stagedFlag) -- \(shellSingleQuoted(path))"
        case ToolDefinition.gitStageHunk.name:
            command = try remoteGitHunkCommand(
                path: try args.requiredString("path"),
                patch: try args.requiredString("patch"),
                applyArguments: ["--cached", "--whitespace=nowarn"],
                successMessage: "Hunk staged.\\n"
            )
        case ToolDefinition.gitRestoreHunk.name:
            command = try remoteGitHunkCommand(
                path: try args.requiredString("path"),
                patch: try args.requiredString("patch"),
                applyArguments: ["--reverse", "--whitespace=nowarn"],
                successMessage: "Hunk restored.\\n"
            )
        case ToolDefinition.gitCommit.name:
            let message = try args.requiredString("message").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                throw GitToolError.emptyCommitMessage
            }
            command = "git commit -m \(shellSingleQuoted(message))"
        case ToolDefinition.gitPush.name:
            command = try remoteGitPushCommand(
                remote: args.string("remote"),
                branch: args.string("branch"),
                setUpstream: args.bool("setUpstream") ?? false
            )
        case ToolDefinition.gitPullRequestCreate.name:
            command = try remoteGitPullRequestCommand(
                title: args.string("title"),
                body: args.string("body"),
                base: args.string("base"),
                head: args.string("head"),
                draft: args.bool("draft") ?? false,
                fill: args.bool("fill") ?? false
            )
        case ToolDefinition.gitPullRequestView.name:
            command = try remoteGitPullRequestViewCommand(selector: args.string("selector"))
        case ToolDefinition.gitPullRequestChecks.name:
            command = try remoteGitPullRequestChecksCommand(selector: args.string("selector"))
        case ToolDefinition.gitPullRequestDiff.name:
            command = try remoteGitPullRequestDiffCommand(selector: args.string("selector"))
        case ToolDefinition.gitPullRequestCheckout.name:
            command = try remoteGitPullRequestCheckoutCommand(
                selector: args.string("selector"),
                branch: args.string("branch")
            )
        case ToolDefinition.gitPullRequestReviewers.name:
            command = try remoteGitPullRequestReviewersCommand(
                selector: args.string("selector"),
                add: args.stringArray("add"),
                remove: args.stringArray("remove")
            )
        case ToolDefinition.gitPullRequestLabels.name:
            command = try remoteGitPullRequestLabelsCommand(
                selector: args.string("selector"),
                add: args.stringArray("add"),
                remove: args.stringArray("remove")
            )
        case ToolDefinition.gitPullRequestComment.name:
            command = try remoteGitPullRequestCommentCommand(
                selector: args.string("selector"),
                body: try args.requiredString("body")
            )
        case ToolDefinition.gitPullRequestReview.name:
            command = try remoteGitPullRequestReviewCommand(
                selector: args.string("selector"),
                action: try args.requiredString("action"),
                body: args.string("body")
            )
        case ToolDefinition.gitPullRequestMerge.name:
            command = try remoteGitPullRequestMergeCommand(
                selector: args.string("selector"),
                method: args.string("method"),
                auto: args.bool("auto") ?? false,
                deleteBranch: args.bool("deleteBranch") ?? false
            )
        case ToolDefinition.gitWorktreeList.name:
            command = "git worktree list --porcelain"
        case ToolDefinition.gitWorktreeCreate.name:
            let worktreePath = try WorkspaceRemoteProjectPath.worktreePath(
                try args.requiredString("path"),
                connection: connection
            )
            command = try remoteGitWorktreeCreateCommand(
                worktreePath: worktreePath,
                branch: args.string("branch"),
                base: args.string("base")
            )
            artifacts = [WorkspaceRemoteProjectPath.artifactPath(connection: connection, absolutePath: worktreePath)]
        case ToolDefinition.gitWorktreeRemove.name:
            let worktreePath = try WorkspaceRemoteProjectPath.worktreePath(
                try args.requiredString("path"),
                connection: connection
            )
            command = remoteGitWorktreeRemoveCommand(
                worktreePath: worktreePath,
                force: args.bool("force") ?? false
            )
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }

        return WorkspaceRemoteGitToolRequest(
            command: command,
            artifacts: artifacts,
            extractsPullRequestURLs: pullRequestURLToolNames.contains(call.name)
        )
    }

    private static func remoteGitPushCommand(
        remote: String?,
        branch: String?,
        setUpstream: Bool
    ) throws -> String {
        let remoteName = try GitInputValidator.safeName(
            GitInputValidator.trimmedNonEmpty(remote) ?? "origin"
        )
        let upstreamArguments = setUpstream ? "-u " : ""
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            let branchName = try GitInputValidator.safeName(branch)
            return "git push \(upstreamArguments)\(shellSingleQuoted(remoteName)) \(shellSingleQuoted(branchName))"
        }

        let invalidBranchMessage = shellSingleQuoted(String(describing: GitToolError.invalidGitName("$branch")))
        return [
            "branch=$(git branch --show-current)",
            "test -n \"$branch\" || { printf '%s\\n' \(shellSingleQuoted(String(describing: GitToolError.noCurrentBranch))) >&2; exit 1; }",
            "case \"$branch\" in -*|*..*|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._/-]*) printf '%s\\n' \(invalidBranchMessage) >&2; exit 1;; esac",
            "git push \(upstreamArguments)\(shellSingleQuoted(remoteName)) \"$branch\""
        ].joined(separator: " && ")
    }

    private static func remoteGitPullRequestCommand(
        title: String?,
        body: String?,
        base: String?,
        head: String?,
        draft: Bool,
        fill: Bool
    ) throws -> String {
        let trimmedTitle = GitInputValidator.trimmedNonEmpty(title)
        guard fill || trimmedTitle != nil else {
            throw GitToolError.emptyPullRequestTitle
        }

        var arguments = ["gh", "pr", "create"]
        if let trimmedTitle {
            arguments += ["--title", trimmedTitle]
        }
        if let body = GitInputValidator.trimmedNonEmpty(body) {
            arguments += ["--body", body]
        }
        if let base = GitInputValidator.trimmedNonEmpty(base) {
            arguments += ["--base", try GitInputValidator.safeName(base)]
        }
        if let head = GitInputValidator.trimmedNonEmpty(head) {
            arguments += ["--head", try GitInputValidator.safeName(head)]
        }
        if draft {
            arguments.append("--draft")
        }
        if fill {
            arguments.append("--fill")
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestViewCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments.append("--comments")
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestChecksCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "checks"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestDiffCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "diff"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestCheckoutCommand(selector: String?, branch: String?) throws -> String {
        var arguments = ["gh", "pr", "checkout"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitInputValidator.safeName(branch)]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestReviewersCommand(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let reviewersToAdd = try GitHubPullRequestToolExecutor.safeReviewers(add)
        let reviewersToRemove = try GitHubPullRequestToolExecutor.safeReviewers(remove)
        guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestReviewers
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        if !reviewersToAdd.isEmpty {
            arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
        }
        if !reviewersToRemove.isEmpty {
            arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestLabelsCommand(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let labelsToAdd = try GitHubPullRequestToolExecutor.safeLabels(add)
        let labelsToRemove = try GitHubPullRequestToolExecutor.safeLabels(remove)
        guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestLabels
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        if !labelsToAdd.isEmpty {
            arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
        }
        if !labelsToRemove.isEmpty {
            arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestCommentCommand(
        selector: String?,
        body: String
    ) throws -> String {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }

        var arguments = ["gh", "pr", "comment"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments += ["--body", body]
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestReviewCommand(
        selector: String?,
        action: String,
        body: String?
    ) throws -> String {
        let flag = try GitHubPullRequestToolExecutor.safeReviewFlag(action)
        let body = GitInputValidator.trimmedNonEmpty(body)
        guard flag == "--approve" || body != nil else {
            throw GitToolError.emptyPullRequestReviewBody
        }

        var arguments = ["gh", "pr", "review"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(flag)
        if let body {
            arguments += ["--body", body]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestMergeCommand(
        selector: String?,
        method: String?,
        auto: Bool,
        deleteBranch: Bool
    ) throws -> String {
        var arguments = ["gh", "pr", "merge"]
        if let selector = try GitHubPullRequestToolExecutor.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(try GitHubPullRequestToolExecutor.safeMergeFlag(method))
        if auto {
            arguments.append("--auto")
        }
        if deleteBranch {
            arguments.append("--delete-branch")
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitWorktreeCreateCommand(
        worktreePath: String,
        branch: String?,
        base: String?
    ) throws -> String {
        var arguments = ["git", "worktree", "add"]
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            arguments += ["-b", try GitInputValidator.safeName(branch)]
        }
        arguments.append(worktreePath)
        if let base = GitInputValidator.trimmedNonEmpty(base) {
            arguments.append(try GitInputValidator.safeName(base))
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitWorktreeRemoveCommand(
        worktreePath: String,
        force: Bool
    ) -> String {
        let forceFlag = force ? " --force" : ""
        return [
            "worktree=\(shellSingleQuoted(worktreePath))",
            "git worktree list --porcelain | grep -F -x -- \"worktree $worktree\" >/dev/null || { printf 'Git worktree is not registered: %s\\n' \"$worktree\" >&2; exit 1; }",
            "git worktree remove\(forceFlag) -- \"$worktree\""
        ].joined(separator: " && ")
    }

    private static func remoteGitHunkCommand(
        path: String,
        patch: String,
        applyArguments: [String],
        successMessage: String
    ) throws -> String {
        let relativePath = try WorkspaceRemoteProjectPath.relativePath(path)
        var normalizedPatch = patch
        let trimmedPatch = normalizedPatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPatch.isEmpty else {
            throw GitToolError.emptyPatch
        }
        if let mismatch = GitPatchToolExecutor.mismatchedPatchPath(
            in: normalizedPatch,
            expectedPath: relativePath
        ) {
            throw GitToolError.patchPathMismatch(mismatch)
        }
        if !normalizedPatch.hasSuffix("\n") {
            normalizedPatch.append("\n")
        }

        let encoded = Data(normalizedPatch.utf8).base64EncodedString()
        let flags = applyArguments.map(shellSingleQuoted).joined(separator: " ")
        return [
            "patch_file=\"${TMPDIR:-/tmp}/quillcode-hunk.$$.patch\"",
            "trap 'rm -f \"$patch_file\"' EXIT",
            "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
            "git apply \(flags) --check \"$patch_file\"",
            "git apply \(flags) \"$patch_file\"",
            "printf \(shellSingleQuoted(successMessage))"
        ].joined(separator: " && ")
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalEngine.shellSingleQuoted(value)
    }
}

private enum WorkspaceRemoteGitToolRequestPlannerError: Error, CustomStringConvertible {
    case unsupportedTool(String)

    var description: String {
        switch self {
        case .unsupportedTool(let name):
            return "Tool is not available for SSH Remote projects: \(name)"
        }
    }
}
