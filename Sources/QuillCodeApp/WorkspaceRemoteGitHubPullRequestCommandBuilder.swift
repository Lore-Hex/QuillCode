import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestChecks.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestReviewThread.name,
        ToolDefinition.gitPullRequestMerge.name
    ]

    private static let urlArtifactToolNames: Set<String> = [
        ToolDefinition.gitPullRequestCreate.name,
        ToolDefinition.gitPullRequestView.name,
        ToolDefinition.gitPullRequestDiff.name,
        ToolDefinition.gitPullRequestCheckout.name,
        ToolDefinition.gitPullRequestReviewers.name,
        ToolDefinition.gitPullRequestLabels.name,
        ToolDefinition.gitPullRequestComment.name,
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestMerge.name
    ]

    static func extractsURLs(for toolName: String) -> Bool {
        urlArtifactToolNames.contains(toolName)
    }

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
        case ToolDefinition.gitPullRequestReviewers.name:
            return try reviewers(selector: args.string("selector"), add: args.stringArray("add"), remove: args.stringArray("remove"))
        case ToolDefinition.gitPullRequestLabels.name:
            return try labels(selector: args.string("selector"), add: args.stringArray("add"), remove: args.stringArray("remove"))
        case ToolDefinition.gitPullRequestComment.name:
            return try comment(selector: args.string("selector"), body: try args.requiredString("body"))
        case ToolDefinition.gitPullRequestReview.name:
            return try review(selector: args.string("selector"), action: try args.requiredString("action"), body: args.string("body"))
        case ToolDefinition.gitPullRequestReviewComment.name:
            return try reviewComment(
                selector: args.string("selector"),
                path: try args.requiredString("path"),
                line: try args.requiredInt("line"),
                side: args.string("side"),
                body: try args.requiredString("body"),
                startLine: args.int("startLine"),
                startSide: args.string("startSide")
            )
        case ToolDefinition.gitPullRequestReviewReply.name:
            return try reviewReply(
                selector: args.string("selector"),
                commentID: try args.requiredInt("commentId"),
                body: try args.requiredString("body")
            )
        case ToolDefinition.gitPullRequestReviewThread.name:
            return try reviewThread(
                threadID: try args.requiredString("threadId"),
                action: try args.requiredString("action")
            )
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
        return shellCommand(arguments)
    }

    private static func view(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments.append("--comments")
        return shellCommand(arguments)
    }

    private static func checks(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "checks"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        return shellCommand(arguments)
    }

    private static func diff(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "diff"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        return shellCommand(arguments)
    }

    private static func checkout(selector: String?, branch: String?) throws -> String {
        var arguments = ["gh", "pr", "checkout"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitInputValidator.safeName(branch)]
        }
        return shellCommand(arguments)
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
        return shellCommand(arguments)
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
        return shellCommand(arguments)
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
        return shellCommand(arguments)
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
        return shellCommand(arguments)
    }

    private static func reviewComment(
        selector: String?,
        path: String,
        line: Int,
        side: String?,
        body: String,
        startLine: Int?,
        startSide: String?
    ) throws -> String {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }
        let relativePath = try WorkspaceRemoteProjectPath.relativePath(path)
        let line = try GitHubPullRequestInputValidator.safeReviewLine(line)
        let startLine = try GitHubPullRequestInputValidator.safeReviewStartLine(startLine, line: line)
        let side = try GitHubPullRequestInputValidator.safeReviewSide(side)
        let resolvedStartSide = try startLine.map { _ in
            try GitHubPullRequestInputValidator.safeReviewSide(startSide ?? side)
        }

        var viewArguments = ["gh", "pr", "view"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            viewArguments.append(selector)
        }
        viewArguments += ["--json", "number,headRefOid", "--jq", ".number + \" \" + .headRefOid"]

        var apiFields = [
            quoted("--raw-field"), quoted("body=\(body)"),
            quoted("--raw-field"), "\"commit_id=${head_oid}\"",
            quoted("--raw-field"), quoted("path=\(relativePath)"),
            quoted("--field"), quoted("line=\(line)"),
            quoted("--raw-field"), quoted("side=\(side)")
        ]
        if let startLine {
            apiFields += [quoted("--field"), quoted("start_line=\(startLine)")]
        }
        if let resolvedStartSide {
            apiFields += [quoted("--raw-field"), quoted("start_side=\(resolvedStartSide)")]
        }

        let apiFieldCommand = apiFields.joined(separator: " ")
        return [
            "pr_data=$(\(shellCommand(viewArguments)))",
            "pr_number=${pr_data%% *}",
            "head_oid=${pr_data#* }",
            "repo=$(\(shellCommand(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])))",
            "gh api \"repos/${repo}/pulls/${pr_number}/comments\" \(apiFieldCommand)"
        ].joined(separator: " && ")
    }

    private static func reviewReply(
        selector: String?,
        commentID: Int,
        body: String
    ) throws -> String {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }
        let commentID = try GitHubPullRequestInputValidator.safeReviewCommentID(commentID)

        var viewArguments = ["gh", "pr", "view"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            viewArguments.append(selector)
        }
        viewArguments += ["--json", "number", "--jq", ".number"]

        return [
            "pr_number=$(\(shellCommand(viewArguments)))",
            "repo=$(\(shellCommand(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])))",
            "gh api \"repos/${repo}/pulls/${pr_number}/comments/\(commentID)/replies\" \(quoted("--raw-field")) \(quoted("body=\(body)"))"
        ].joined(separator: " && ")
    }

    private static func reviewThread(
        threadID: String,
        action: String
    ) throws -> String {
        let threadID = try GitHubPullRequestInputValidator.safeReviewThreadID(threadID)
        let action = try GitHubPullRequestInputValidator.safeReviewThreadAction(action)
        return shellCommand([
            "gh",
            "api",
            "graphql",
            "--raw-field",
            "threadId=\(threadID)",
            "--raw-field",
            "query=\(reviewThreadMutation(for: action))"
        ])
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
        return shellCommand(arguments)
    }

    private static func reviewThreadMutation(for action: String) -> String {
        let mutation = action == "resolve" ? "resolveReviewThread" : "unresolveReviewThread"
        let nonNull = "\u{21}"
        return "mutation($threadId: ID\(nonNull)) { \(mutation)(input: {threadId: $threadId}) { thread { id isResolved } } }"
    }

    private static func shellCommand(_ arguments: [String]) -> String {
        arguments.map(WorkspaceTerminalSessionAdapter.shellSingleQuoted).joined(separator: " ")
    }

    private static func quoted(_ argument: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(argument)
    }
}
