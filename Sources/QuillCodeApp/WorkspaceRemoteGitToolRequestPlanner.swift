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
        case let name where WorkspaceRemoteGitHunkCommandBuilder.toolNames.contains(name):
            command = try WorkspaceRemoteGitHunkCommandBuilder.command(for: call, arguments: args)
        case ToolDefinition.gitCommit.name:
            let message = try args.requiredString("message").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !message.isEmpty else {
                throw GitToolError.emptyCommitMessage
            }
            command = "git commit -m \(shellSingleQuoted(message))"
        case ToolDefinition.gitPush.name:
            command = try WorkspaceRemoteGitPushCommandBuilder.command(arguments: args)
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
