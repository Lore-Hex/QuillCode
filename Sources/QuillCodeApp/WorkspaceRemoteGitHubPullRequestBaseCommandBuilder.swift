import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestBaseCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestList.name,
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
        case ToolDefinition.gitPullRequestList.name:
            return try list(state: args.string("state"), limit: args.int("limit"))
        case ToolDefinition.gitPullRequestCreate.name:
            return try create(
                title: args.string("title"),
                body: args.string("body"),
                base: args.string("base"),
                head: args.string("head"),
                draft: args.bool("draft") ?? false,
                fill: args.bool("fill") ?? false
            )
        case ToolDefinition.gitPullRequestView.name:
            return try view(selector: args.string("selector"))
        case ToolDefinition.gitPullRequestChecks.name:
            return try checks(selector: args.string("selector"))
        case ToolDefinition.gitPullRequestDiff.name:
            return try diff(selector: args.string("selector"))
        case ToolDefinition.gitPullRequestCheckout.name:
            return try checkout(selector: args.string("selector"), branch: args.string("branch"))
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    static func list(state: String?, limit: Int?) throws -> String {
        var arguments = ["gh", "pr", "list"]
        if let state = try GitHubPullRequestInputValidator.safeListState(state) {
            arguments += ["--state", state]
        }
        if let limit = try GitHubPullRequestInputValidator.safeListLimit(limit) {
            arguments += ["--limit", String(limit)]
        }
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }

    static func create(
        title: String?,
        body: String?,
        base: String?,
        head: String?,
        draft: Bool,
        fill: Bool
    ) throws -> String {
        let trimmedTitle = GitInputValidator.trimmedNonEmpty(title)
        guard fill || trimmedTitle != nil else {
            throw GitToolError.emptyPullRequestTitle
        }

        var arguments = ["gh", "pr", "create"]
        if let trimmedTitle {
            arguments += ["--title", trimmedTitle]
        }
        if let body = GitInputValidator.trimmedNonEmpty(body) {
            arguments += ["--body", body]
        }
        if let base = GitInputValidator.trimmedNonEmpty(base) {
            arguments += ["--base", try GitInputValidator.safeName(base)]
        }
        if let head = GitInputValidator.trimmedNonEmpty(head) {
            arguments += ["--head", try GitInputValidator.safeName(head)]
        }
        if draft {
            arguments.append("--draft")
        }
        if fill {
            arguments.append("--fill")
        }
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }

    static func view(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments.append("--comments")
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }

    static func checks(selector: String?) throws -> String {
        try selectorCommand(subcommand: "checks", selector: selector)
    }

    static func diff(selector: String?) throws -> String {
        try selectorCommand(subcommand: "diff", selector: selector)
    }

    static func checkout(selector: String?, branch: String?) throws -> String {
        var arguments = ["gh", "pr", "checkout"]
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitInputValidator.safeName(branch)]
        }
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }

    private static func selectorCommand(subcommand: String, selector: String?) throws -> String {
        var arguments = ["gh", "pr", subcommand]
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }
}
