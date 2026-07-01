import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

struct WorkspaceRemoteProjectToolExecutor: Sendable, Hashable {
    static let toolDefinitions = WorkspaceRemoteProjectToolCatalog.toolDefinitions
    static let gitToolNames = WorkspaceRemoteProjectToolCatalog.gitToolNames

    static func executionOverride(
        project: ProjectRef?,
        executor: SSHRemoteShellExecutor
    ) -> AgentToolExecutionOverride? {
        guard let project, project.isRemote else { return nil }
        return { call, _ in
            executeIfSupported(
                call,
                context: .init(connection: project.connection, executor: executor)
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
        executeIfSupported(
            call,
            context: .init(connection: connection, executor: executor)
        )
            ?? unavailableToolResult(call.name)
    }

    static func executeIfSupported(
        _ call: ToolCall,
        connection: ProjectConnection,
        executor: SSHRemoteShellExecutor
    ) -> ToolResult? {
        executeIfSupported(
            call,
            context: .init(connection: connection, executor: executor)
        )
    }

    private static func executeIfSupported(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) -> ToolResult? {
        switch call.name {
        case ToolDefinition.shellRun.name:
            return executeRemoteShellToolCall(
                call,
                context: context
            )
        case ToolDefinition.fileRead.name, ToolDefinition.fileList.name, ToolDefinition.fileWrite.name:
            return WorkspaceRemoteProjectFileToolExecutor.execute(
                call,
                context: context
            )
        case ToolDefinition.applyPatch.name:
            return executeRemotePatchToolCall(
                call,
                context: context
            )
        case let name where Self.gitToolNames.contains(name):
            return executeRemoteGitToolCall(
                call,
                context: context
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
        context: WorkspaceRemoteProjectToolExecutionContext
    ) -> ToolResult {
        do {
            let plannedRequest = try WorkspaceRemoteGitToolRequestPlanner.request(
                for: call,
                connection: context.connection
            )

            var result = context.run(command: plannedRequest.command)
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

    private static func executeRemotePatchToolCall(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
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

            return context.run(command: command)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func executeRemoteShellToolCall(
        _ call: ToolCall,
        context: WorkspaceRemoteProjectToolExecutionContext
    ) -> ToolResult {
        do {
            let args = try ToolArguments(call.argumentsJSON)
            let command = try args.requiredString("cmd")
            let requestConnection = WorkspaceRemoteProjectPath.shellConnection(
                context.connection,
                cwd: args.string("cwd")
            )
            return context.run(command: command, connection: requestConnection)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(value)
    }
}
