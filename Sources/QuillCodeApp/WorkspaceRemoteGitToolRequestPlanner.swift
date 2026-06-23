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
        case let name where WorkspaceRemoteGitHubPullRequestCommandBuilder.toolNames.contains(name):
            command = try WorkspaceRemoteGitHubPullRequestCommandBuilder.command(for: call, arguments: args)
        case let name where WorkspaceRemoteGitWorktreeCommandBuilder.toolNames.contains(name):
            let worktreePlan = try WorkspaceRemoteGitWorktreeCommandBuilder.plan(
                for: call,
                arguments: args,
                connection: connection
            )
            command = worktreePlan.command
            artifacts = worktreePlan.artifacts
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }

        return WorkspaceRemoteGitToolRequest(
            command: command,
            artifacts: artifacts,
            extractsPullRequestURLs: WorkspaceRemoteGitHubPullRequestCommandBuilder.extractsURLs(for: call.name)
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

enum WorkspaceRemoteGitToolRequestPlannerError: Error, CustomStringConvertible {
    case unsupportedTool(String)

    var description: String {
        switch self {
        case .unsupportedTool(let name):
            return "Tool is not available for SSH Remote projects: \(name)"
        }
    }
}
