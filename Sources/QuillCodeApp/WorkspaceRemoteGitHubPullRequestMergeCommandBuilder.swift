import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestMergeCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestMerge.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        guard call.name == ToolDefinition.gitPullRequestMerge.name else {
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }

        return try merge(
            selector: args.string("selector"),
            method: args.string("method"),
            auto: args.bool("auto") ?? false,
            deleteBranch: args.bool("deleteBranch") ?? false
        )
    }

    static func merge(
        selector: String?,
        method: String?,
        auto: Bool,
        deleteBranch: Bool
    ) throws -> String {
        var arguments = ["gh", "pr", "merge"]
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments.append(try GitHubPullRequestInputValidator.safeMergeFlag(method))
        if auto {
            arguments.append("--auto")
        }
        if deleteBranch {
            arguments.append("--delete-branch")
        }
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }
}
