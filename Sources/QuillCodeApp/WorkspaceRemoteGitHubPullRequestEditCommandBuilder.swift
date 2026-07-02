import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestEditCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestLifecycle.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
        case ToolDefinition.gitPullRequestReviewers.name:
            return try reviewers(
                selector: args.string("selector"),
                add: args.stringArray("add"),
                remove: args.stringArray("remove")
            )
        case ToolDefinition.gitPullRequestLabels.name:
            return try labels(
                selector: args.string("selector"),
                add: args.stringArray("add"),
                remove: args.stringArray("remove")
            )
        case ToolDefinition.gitPullRequestComment.name:
            return try comment(selector: args.string("selector"), body: try args.requiredString("body"))
        case ToolDefinition.gitPullRequestLifecycle.name:
            return try lifecycle(selector: args.string("selector"), action: try args.requiredString("action"))
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    static func reviewers(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let reviewersToAdd = try GitHubPullRequestInputValidator.safeReviewers(add)
        let reviewersToRemove = try GitHubPullRequestInputValidator.safeReviewers(remove)
        guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestReviewers
        }

        return try edit(
            selector: selector,
            additions: reviewersToAdd,
            removals: reviewersToRemove,
            addFlag: "--add-reviewer",
            removeFlag: "--remove-reviewer"
        )
    }

    static func labels(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let labelsToAdd = try GitHubPullRequestInputValidator.safeLabels(add)
        let labelsToRemove = try GitHubPullRequestInputValidator.safeLabels(remove)
        guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestLabels
        }

        return try edit(
            selector: selector,
            additions: labelsToAdd,
            removals: labelsToRemove,
            addFlag: "--add-label",
            removeFlag: "--remove-label"
        )
    }

    static func comment(selector: String?, body: String) throws -> String {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }

        var arguments = ["gh", "pr", "comment"]
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments += ["--body", body]
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }

    static func lifecycle(selector: String?, action: String) throws -> String {
        let safeAction = try GitHubPullRequestInputValidator.safeLifecycleAction(action)
        var arguments = ["gh", "pr", safeAction]
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }

    private static func edit(
        selector: String?,
        additions: [String],
        removals: [String],
        addFlag: String,
        removeFlag: String
    ) throws -> String {
        var arguments = ["gh", "pr", "edit"]
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        if !additions.isEmpty {
            arguments += [addFlag, additions.joined(separator: ",")]
        }
        if !removals.isEmpty {
            arguments += [removeFlag, removals.joined(separator: ",")]
        }
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }
}
