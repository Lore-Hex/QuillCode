import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestPrimaryCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestMerge.name
    ]

    static let urlArtifactToolNames: Set<String> = [
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestMerge.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
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
        case ToolDefinition.gitPullRequestMerge.name:
            return try merge(
                selector: args.string("selector"),
                method: args.string("method"),
                auto: args.bool("auto") ?? false,
                deleteBranch: args.bool("deleteBranch") ?? false
            )
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    private static func create(
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
        return command(arguments)
    }

    private static func view(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments.append("--comments")
        return command(arguments)
    }

    private static func checks(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "checks"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        return command(arguments)
    }

    private static func diff(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "diff"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        return command(arguments)
    }

    private static func checkout(selector: String?, branch: String?) throws -> String {
        var arguments = ["gh", "pr", "checkout"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitInputValidator.safeName(branch)]
        }
        return command(arguments)
    }

    private static func merge(
        selector: String?,
        method: String?,
        auto: Bool,
        deleteBranch: Bool
    ) throws -> String {
        var arguments = ["gh", "pr", "merge"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments.append(try GitHubPullRequestInputValidator.safeMergeFlag(method))
        if auto {
            arguments.append("--auto")
        }
        if deleteBranch {
            arguments.append("--delete-branch")
        }
        return command(arguments)
    }

    private static func command(_ arguments: [String]) -> String {
        WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }
}
