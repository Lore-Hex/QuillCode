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
        case let name where WorkspaceRemoteGitBasicCommandBuilder.toolNames.contains(name):
            command = try WorkspaceRemoteGitBasicCommandBuilder.command(for: call, arguments: args)
        case let name where WorkspaceRemoteGitHunkCommandBuilder.toolNames.contains(name):
            command = try WorkspaceRemoteGitHunkCommandBuilder.command(for: call, arguments: args)
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
