import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestCommandBuilder {
    static let toolNames: Set<String> = WorkspaceRemoteGitHubPullRequestPrimaryCommandBuilder.toolNames
        .union(WorkspaceRemoteGitHubPullRequestCollaborationCommandBuilder.toolNames)
        .union(WorkspaceRemoteGitHubPullRequestReviewThreadCommandBuilder.toolNames)

    private static let urlArtifactToolNames: Set<String> =
        WorkspaceRemoteGitHubPullRequestPrimaryCommandBuilder.urlArtifactToolNames
            .union(WorkspaceRemoteGitHubPullRequestCollaborationCommandBuilder.urlArtifactToolNames)
            .union(WorkspaceRemoteGitHubPullRequestReviewThreadCommandBuilder.urlArtifactToolNames)

    static func extractsURLs(for toolName: String) -> Bool {
        urlArtifactToolNames.contains(toolName)
    }

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
        case let name where WorkspaceRemoteGitHubPullRequestPrimaryCommandBuilder.toolNames.contains(name):
            return try WorkspaceRemoteGitHubPullRequestPrimaryCommandBuilder.command(for: call, arguments: args)
        case let name where WorkspaceRemoteGitHubPullRequestCollaborationCommandBuilder.toolNames.contains(name):
            return try WorkspaceRemoteGitHubPullRequestCollaborationCommandBuilder.command(for: call, arguments: args)
        case let name where WorkspaceRemoteGitHubPullRequestReviewThreadCommandBuilder.toolNames.contains(name):
            return try WorkspaceRemoteGitHubPullRequestReviewThreadCommandBuilder.command(for: call, arguments: args)
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }
}
