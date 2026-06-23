import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteProjectToolExecutor: Sendable, Hashable {
    static let toolDefinitions: [ToolDefinition] = [
        .shellRun,
        .fileRead,
        .fileWrite,
        .applyPatch,
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
        .gitWorktreeRemove
    ]

    static let gitToolNames: Set<String> = [
        ToolDefinition.gitStatus.name,
        ToolDefinition.gitDiff.name,
        ToolDefinition.gitStage.name,
        ToolDefinition.gitRestore.name,
        ToolDefinition.gitStageHunk.name,
        ToolDefinition.gitRestoreHunk.name,
        ToolDefinition.gitCommit.name,
        ToolDefinition.gitPush.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestMerge.name,
        ToolDefinition.gitWorktreeList.name,
        ToolDefinition.gitWorktreeCreate.name,
        ToolDefinition.gitWorktreeRemove.name
    ]

    static func executionOverride(
        project: ProjectRef?,
        executor: SSHRemoteShellExecutor
    ) -> AgentToolExecutionOverride? {
        guard let project, project.isRemote else { return nil }
        return { call, _ in
            executeIfSupported(
                call,
                connection: project.connection,
                executor: executor
            )
        }
    }

    static func execute(
        _ call: ToolCall,
        project: ProjectRef,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        guard project.isRemote else {
            return unavailableToolResult(call.name)
        }
        return execute(call, connection: project.connection, executor: executor)
    }

    static func execute(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        executeIfSupported(call, connection: connection, executor: executor)
            ?? unavailableToolResult(call.name)
    }

    static func executeIfSupported(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult? {
        switch call.name {
        case ToolDefinition.shellRun.name:
            return executeRemoteShellToolCall(
                call,
                connection: connection,
                executor: executor
            )
        case ToolDefinition.fileRead.name, ToolDefinition.fileWrite.name:
            return executeRemoteFileToolCall(
                call,
                connection: connection,
                executor: executor
            )
        case ToolDefinition.applyPatch.name:
            return executeRemotePatchToolCall(
                call,
                connection: connection,
                executor: executor
            )
        case let name where Self.gitToolNames.contains(name):
            return executeRemoteGitToolCall(
                call,
                connection: connection,
                executor: executor
            )
        default:
            return nil
        }
    }

    private static func unavailableToolResult(_ toolName: String) -> ToolResult {
        ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(toolName)")
    }

    private static func executeRemoteGitToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command: String
            var artifacts: [String] = []
            switch call.name {
            case ToolDefinition.gitStatus.name:
                command = "git status --short --branch"
            case ToolDefinition.gitDiff.name:
                command = args.bool("staged") == true ? "git diff --staged" : "git diff"
            case ToolDefinition.gitStage.name:
                let path = try remoteProjectRelativePath(try args.requiredString("path"))
                command = "git add -- \(shellSingleQuoted(path))"
            case ToolDefinition.gitRestore.name:
                let path = try remoteProjectRelativePath(try args.requiredString("path"))
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
                let worktreePath = try remoteGitWorktreePath(
                    try args.requiredString("path"),
                    connection: connection
                )
                command = remoteGitWorktreeCreateCommand(
                    worktreePath: worktreePath,
                    branch: args.string("branch"),
                    base: args.string("base")
                )
                artifacts = [remoteArtifactPath(connection: connection, absolutePath: worktreePath)]
            case ToolDefinition.gitWorktreeRemove.name:
                let worktreePath = try remoteGitWorktreePath(
                    try args.requiredString("path"),
                    connection: connection
                )
                command = remoteGitWorktreeRemoveCommand(
                    worktreePath: worktreePath,
                    force: args.bool("force") ?? false
                )
            default:
                return ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
            }

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if [
                ToolDefinition.gitPullRequestCreate.name,
                ToolDefinition.gitPullRequestView.name,
                ToolDefinition.gitPullRequestDiff.name,
                ToolDefinition.gitPullRequestCheckout.name,
                ToolDefinition.gitPullRequestReviewers.name,
                ToolDefinition.gitPullRequestLabels.name,
                ToolDefinition.gitPullRequestComment.name,
                ToolDefinition.gitPullRequestReview.name,
                ToolDefinition.gitPullRequestMerge.name
            ].contains(call.name), result.ok {
                result.artifacts = GitToolExecutor.extractURLs(from: result.stdout)
            } else if result.ok, !artifacts.isEmpty {
                result.artifacts = artifacts
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func remoteGitPushCommand(
        remote: String?,
        branch: String?,
        setUpstream: Bool
    ) throws -> String {
        let remoteName = try GitToolExecutor.safeGitName(
            GitToolExecutor.trimmedNonEmpty(remote) ?? "origin"
        )
        let upstreamArguments = setUpstream ? "-u " : ""
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            let branchName = try GitToolExecutor.safeGitName(branch)
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
        let trimmedTitle = GitToolExecutor.trimmedNonEmpty(title)
        guard fill || trimmedTitle != nil else {
            throw GitToolError.emptyPullRequestTitle
        }

        var arguments = ["gh", "pr", "create"]
        if let trimmedTitle {
            arguments += ["--title", trimmedTitle]
        }
        if let body = GitToolExecutor.trimmedNonEmpty(body) {
            arguments += ["--body", body]
        }
        if let base = GitToolExecutor.trimmedNonEmpty(base) {
            arguments += ["--base", try GitToolExecutor.safeGitName(base)]
        }
        if let head = GitToolExecutor.trimmedNonEmpty(head) {
            arguments += ["--head", try GitToolExecutor.safeGitName(head)]
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
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append("--comments")
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestChecksCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "checks"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestDiffCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "diff"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestCheckoutCommand(selector: String?, branch: String?) throws -> String {
        var arguments = ["gh", "pr", "checkout"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitToolExecutor.safeGitName(branch)]
        }
        return arguments.map(shellSingleQuoted).joined(separator: " ")
    }

    private static func remoteGitPullRequestReviewersCommand(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let reviewersToAdd = try GitToolExecutor.safePullRequestReviewers(add)
        let reviewersToRemove = try GitToolExecutor.safePullRequestReviewers(remove)
        guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestReviewers
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
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
        let labelsToAdd = try GitToolExecutor.safePullRequestLabels(add)
        let labelsToRemove = try GitToolExecutor.safePullRequestLabels(remove)
        guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestLabels
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
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
        guard let body = GitToolExecutor.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }

        var arguments = ["gh", "pr", "comment"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
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
        let flag = try GitToolExecutor.safePullRequestReviewFlag(action)
        let body = GitToolExecutor.trimmedNonEmpty(body)
        guard flag == "--approve" || body != nil else {
            throw GitToolError.emptyPullRequestReviewBody
        }

        var arguments = ["gh", "pr", "review"]
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
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
        if let selector = try GitToolExecutor.safePullRequestSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(try GitToolExecutor.safePullRequestMergeFlag(method))
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
    ) -> String {
        var arguments = ["git", "worktree", "add"]
        if let branch = GitToolExecutor.trimmedNonEmpty(branch) {
            arguments += ["-b", branch]
        }
        arguments.append(worktreePath)
        if let base = GitToolExecutor.trimmedNonEmpty(base) {
            arguments.append(base)
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

    private static func remoteGitWorktreePath(
        _ rawPath: String,
        connection: ProjectConnection
    ) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw GitToolError.emptyPath
        }
        guard let workspace = normalizedAbsolutePOSIXPath(connection.path) else {
            throw GitToolError.outsideWorkspace(connection.path)
        }
        let parent = posixParentPath(workspace)
        let candidateRaw = trimmed.hasPrefix("/") ? trimmed : "\(parent)/\(trimmed)"
        guard let candidate = normalizedAbsolutePOSIXPath(candidateRaw),
              isPOSIXPath(candidate, inside: parent) else {
            throw GitToolError.outsideWorkspace(rawPath)
        }
        guard candidate != workspace else {
            throw GitToolError.mainWorkspaceWorktreePath
        }
        return candidate
    }

    private static func normalizedAbsolutePOSIXPath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil else {
            return nil
        }
        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        return components.isEmpty ? "/" : "/\(components.joined(separator: "/"))"
    }

    private static func posixParentPath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count > 1 else { return "/" }
        return "/\(components.dropLast().joined(separator: "/"))"
    }

    private static func isPOSIXPath(_ path: String, inside parent: String) -> Bool {
        if parent == "/" {
            return path.hasPrefix("/")
        }
        return path == parent || path.hasPrefix("\(parent)/")
    }

    private static func remoteGitHunkCommand(
        path: String,
        patch: String,
        applyArguments: [String],
        successMessage: String
    ) throws -> String {
        let relativePath = try remoteProjectRelativePath(path)
        var normalizedPatch = patch
        let trimmedPatch = normalizedPatch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPatch.isEmpty else {
            throw GitToolError.emptyPatch
        }
        if let mismatch = GitToolExecutor.mismatchedPatchPath(
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

    private static func executeRemoteFileToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let relativePath = try remoteProjectRelativePath(try args.requiredString("path"))
            let command: String
            switch call.name {
            case ToolDefinition.fileRead.name:
                command = "cat -- \(shellSingleQuoted(relativePath))"
            case ToolDefinition.fileWrite.name:
                let content = try args.requiredString("content")
                let encoded = Data(content.utf8).base64EncodedString()
                let directory = remoteDirectory(for: relativePath)
                command = [
                    "mkdir -p -- \(shellSingleQuoted(directory))",
                    "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \(shellSingleQuoted(relativePath))",
                    "printf 'Wrote %s\\n' \(shellSingleQuoted(relativePath))"
                ].joined(separator: " && ")
            default:
                return ToolResult(ok: false, error: "Tool is not available for SSH Remote projects: \(call.name)")
            }

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if result.ok {
                result.artifacts = [remoteArtifactPath(connection: connection, relativePath: relativePath)]
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func executeRemotePatchToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            var patch = try args.requiredString("patch")
            let trimmedPatch = patch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPatch.isEmpty else {
                return ToolResult(ok: false, error: String(describing: PatchToolError.emptyPatch))
            }
            if let unsafePath = PatchToolExecutor.unsafePath(in: patch) {
                return ToolResult(
                    ok: false,
                    error: String(describing: PatchToolError.unsafePath(unsafePath))
                )
            }
            if !patch.hasSuffix("\n") {
                patch.append("\n")
            }

            let encoded = Data(patch.utf8).base64EncodedString()
            let command = [
                "patch_file=\"${TMPDIR:-/tmp}/quillcode.$$.patch\"",
                "trap 'rm -f \"$patch_file\"' EXIT",
                "printf %s \(shellSingleQuoted(encoded)) | base64 --decode > \"$patch_file\"",
                "git apply --check \"$patch_file\"",
                "git apply \"$patch_file\"",
                "printf 'Patch applied.\\n'"
            ].joined(separator: " && ")

            guard let request = executor.request(command: command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func executeRemoteShellToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command = try args.requiredString("cmd")
            let requestConnection = remoteShellConnection(
                connection,
                cwd: args.string("cwd")
            )
            guard let request = executor.request(command: command, connection: requestConnection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            return ShellToolExecutor().run(request)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func remoteProjectRelativePath(_ rawPath: String) throws -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.hasPrefix("~"),
              !trimmed.contains("\0"),
              trimmed.rangeOfCharacter(from: .newlines) == nil
        else {
            throw FileToolError.outsideWorkspace(rawPath)
        }

        var components: [String] = []
        for component in trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch component {
            case ".":
                continue
            case "..":
                throw FileToolError.outsideWorkspace(rawPath)
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else {
            throw FileToolError.outsideWorkspace(rawPath)
        }
        return components.joined(separator: "/")
    }

    private static func remoteDirectory(for relativePath: String) -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        return directory.isEmpty || directory == "." ? "." : directory
    }

    private static func remoteArtifactPath(
        connection: ProjectConnection,
        relativePath: String
    ) -> String {
        var copy = connection
        copy.path = remotePath(connection.path, appending: relativePath)
        return copy.displayLabel
    }

    private static func remoteArtifactPath(
        connection: ProjectConnection,
        absolutePath: String
    ) -> String {
        var copy = connection
        copy.path = absolutePath
        return copy.displayLabel
    }

    private static func remoteShellConnection(
        _ connection: ProjectConnection,
        cwd: String?
    ) -> ProjectConnection {
        let trimmedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedCWD.isEmpty else { return connection }
        var copy = connection
        if trimmedCWD.hasPrefix("/") || trimmedCWD.hasPrefix("~") {
            copy.path = trimmedCWD
        } else {
            copy.path = remotePath(connection.path, appending: trimmedCWD)
        }
        return copy
    }

    private static func remotePath(_ base: String, appending relativePath: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelative = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRelative.isEmpty else { return trimmedBase.isEmpty ? "~" : trimmedBase }

        let isAbsolute = trimmedBase.hasPrefix("/")
        let isHome = trimmedBase == "~" || trimmedBase.hasPrefix("~/")
        let baseRemainder: String
        if isAbsolute {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if isHome {
            baseRemainder = String(trimmedBase.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            baseRemainder = trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }

        var components: [String] = []
        for component in ([baseRemainder, trimmedRelative].filter { !$0.isEmpty }.joined(separator: "/")).split(separator: "/") {
            switch component {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                } else if !isAbsolute && !isHome {
                    components.append(String(component))
                }
            default:
                components.append(String(component))
            }
        }

        let suffix = components.joined(separator: "/")
        if isAbsolute {
            return "/" + suffix
        }
        if isHome || trimmedBase.isEmpty {
            return suffix.isEmpty ? "~" : "~/" + suffix
        }
        return suffix.isEmpty ? "." : suffix
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalEngine.shellSingleQuoted(value)
    }
}
