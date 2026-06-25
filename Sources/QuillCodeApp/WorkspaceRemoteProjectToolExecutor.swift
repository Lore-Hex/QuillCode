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
        .gitWorktreeOpen,
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
        ToolDefinition.gitWorktreeOpen.name,
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
            let plannedRequest = try WorkspaceRemoteGitToolRequestPlanner.request(
                for: call,
                connection: connection
            )

            guard let request = executor.request(command: plannedRequest.command, connection: connection) else {
                return ToolResult(ok: false, error: "SSH Remote project is missing a usable host.")
            }
            var result = ShellToolExecutor().run(request)
            if plannedRequest.extractsPullRequestURLs, result.ok {
                result.artifacts = GitHubPullRequestOutputParser.extractURLs(from: result.stdout)
            } else if result.ok, !plannedRequest.artifacts.isEmpty {
                result.artifacts = plannedRequest.artifacts
            }
            return result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func executeRemoteFileToolCall(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let relativePath = try WorkspaceRemoteProjectPath.relativePath(try args.requiredString("path"))
            let command: String
            switch call.name {
            case ToolDefinition.fileRead.name:
                command = "cat -- \(shellSingleQuoted(relativePath))"
            case ToolDefinition.fileWrite.name:
                let content = try args.requiredString("content")
                let encoded = Data(content.utf8).base64EncodedString()
                let directory = WorkspaceRemoteProjectPath.directory(for: relativePath)
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
                result.artifacts = [WorkspaceRemoteProjectPath.artifactPath(connection: connection, relativePath: relativePath)]
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
            let requestConnection = WorkspaceRemoteProjectPath.shellConnection(
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

    private static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(value)
    }
}
