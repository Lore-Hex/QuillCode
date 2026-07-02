import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestCommandBuilder {
    static let toolNames = WorkspaceRemoteGitHubPullRequestBaseCommandBuilder.toolNames
        .union(WorkspaceRemoteGitHubPullRequestEditCommandBuilder.toolNames)
        .union(WorkspaceRemoteGitHubPullRequestReviewCommandBuilder.toolNames)
        .union(WorkspaceRemoteGitHubPullRequestMergeCommandBuilder.toolNames)

    private static let urlArtifactToolNames: Set<String> = [
        ToolDefinition.gitPullRequestList.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestLifecycle.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestMerge.name
    ]

    static func extractsURLs(for toolName: String) -> Bool {
        urlArtifactToolNames.contains(toolName)
    }

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        if WorkspaceRemoteGitHubPullRequestBaseCommandBuilder.toolNames.contains(call.name) {
            return try WorkspaceRemoteGitHubPullRequestBaseCommandBuilder.command(for: call, arguments: args)
        }
        if WorkspaceRemoteGitHubPullRequestEditCommandBuilder.toolNames.contains(call.name) {
            return try WorkspaceRemoteGitHubPullRequestEditCommandBuilder.command(for: call, arguments: args)
        }
        if WorkspaceRemoteGitHubPullRequestReviewCommandBuilder.toolNames.contains(call.name) {
            return try WorkspaceRemoteGitHubPullRequestReviewCommandBuilder.command(for: call, arguments: args)
        }
        if WorkspaceRemoteGitHubPullRequestMergeCommandBuilder.toolNames.contains(call.name) {
            return try WorkspaceRemoteGitHubPullRequestMergeCommandBuilder.command(for: call, arguments: args)
        }
        throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
    }
}
