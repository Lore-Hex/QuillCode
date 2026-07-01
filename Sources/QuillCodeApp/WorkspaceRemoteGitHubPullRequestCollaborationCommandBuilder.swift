import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestCollaborationCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name
    ]

    static let urlArtifactToolNames = toolNames

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
        case ToolDefinition.gitPullRequestReview.name:
            return try review(
                selector: args.string("selector"),
                action: try args.requiredString("action"),
                body: args.string("body")
            )
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    private static func reviewers(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let reviewersToAdd = try GitHubPullRequestInputValidator.safeReviewers(add)
        let reviewersToRemove = try GitHubPullRequestInputValidator.safeReviewers(remove)
        guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestReviewers
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        if !reviewersToAdd.isEmpty {
            arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
        }
        if !reviewersToRemove.isEmpty {
            arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
        }
        return command(arguments)
    }

    private static func labels(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> String {
        let labelsToAdd = try GitHubPullRequestInputValidator.safeLabels(add)
        let labelsToRemove = try GitHubPullRequestInputValidator.safeLabels(remove)
        guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestLabels
        }

        var arguments = ["gh", "pr", "edit"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        if !labelsToAdd.isEmpty {
            arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
        }
        if !labelsToRemove.isEmpty {
            arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
        }
        return command(arguments)
    }

    private static func comment(selector: String?, body: String) throws -> String {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }

        var arguments = ["gh", "pr", "comment"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments += ["--body", body]
        return command(arguments)
    }

    private static func review(
        selector: String?,
        action: String,
        body: String?
    ) throws -> String {
        let flag = try GitHubPullRequestInputValidator.safeReviewFlag(action)
        let body = GitInputValidator.trimmedNonEmpty(body)
        guard flag == "--approve" || body != nil else {
            throw GitToolError.emptyPullRequestReviewBody
        }

        var arguments = ["gh", "pr", "review"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(flag)
        if let body {
            arguments += ["--body", body]
        }
        return command(arguments)
    }

    private static func command(_ arguments: [String]) -> String {
        WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }
}
