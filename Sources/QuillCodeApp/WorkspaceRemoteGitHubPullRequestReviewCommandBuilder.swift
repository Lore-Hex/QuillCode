import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestReviewCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestReview.name,
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestReviewThreads.name,
        ToolDefinition.gitPullRequestReviewThread.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
        case ToolDefinition.gitPullRequestReview.name:
            return try review(
                selector: args.string("selector"),
                action: try args.requiredString("action"),
                body: args.string("body")
            )
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
        case ToolDefinition.gitPullRequestReviewThreads.name:
            return try reviewThreads(selector: args.string("selector"))
        case ToolDefinition.gitPullRequestReviewThread.name:
            return try reviewThread(
                threadID: try args.requiredString("threadId"),
                action: try args.requiredString("action")
            )
        default:
            throw WorkspaceRemoteGitToolRequestPlannerError.unsupportedTool(call.name)
        }
    }

    static func review(
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
        try WorkspaceRemoteGitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments.append(flag)
        if let body {
            arguments += ["--body", body]
        }
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command(arguments)
    }

    static func reviewComment(
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

        let viewCommand = try pullRequestNumberAndHeadCommand(selector: selector)
        return [
            "pr_data=$(\(viewCommand))",
            "pr_number=${pr_data%% *}",
            "head_oid=${pr_data#* }",
            "repo=$(\(WorkspaceRemoteGitHubPullRequestCommandSupport.repoNameWithOwnerCommand()))",
            "gh api \"repos/${repo}/pulls/${pr_number}/comments\" \(apiFields.joined(separator: " "))"
        ].joined(separator: " && ")
    }

    static func reviewReply(
        selector: String?,
        commentID: Int,
        body: String
    ) throws -> String {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }
        let commentID = try GitHubPullRequestInputValidator.safeReviewCommentID(commentID)

        let bodyField = "\(quoted("--raw-field")) \(quoted("body=\(body)"))"
        return [
            "pr_number=$(\(try pullRequestNumberCommand(selector: selector)))",
            "repo=$(\(WorkspaceRemoteGitHubPullRequestCommandSupport.repoNameWithOwnerCommand()))",
            "gh api \"repos/${repo}/pulls/${pr_number}/comments/\(commentID)/replies\" \(bodyField)"
        ].joined(separator: " && ")
    }

    static func reviewThreads(selector: String?) throws -> String {
        let graphqlFields = [
            quoted("--raw-field"), "\"owner=${owner}\"",
            quoted("--raw-field"), "\"name=${name}\"",
            quoted("--field"), "\"number=${pr_number}\"",
            quoted("--raw-field"), quoted("query=\(GitHubPullRequestReviewThreadsQuery.graphql)")
        ].joined(separator: " ")

        return [
            "pr_number=$(\(try pullRequestNumberCommand(selector: selector)))",
            "repo=$(\(WorkspaceRemoteGitHubPullRequestCommandSupport.repoNameWithOwnerCommand()))",
            "owner=${repo%%/*}",
            "name=${repo#*/}",
            "gh api graphql \(graphqlFields)"
        ].joined(separator: " && ")
    }

    static func reviewThread(
        threadID: String,
        action: String
    ) throws -> String {
        let threadID = try GitHubPullRequestInputValidator.safeReviewThreadID(threadID)
        let action = try GitHubPullRequestInputValidator.safeReviewThreadAction(action)
        return WorkspaceRemoteGitHubPullRequestCommandSupport.command([
            "gh",
            "api",
            "graphql",
            "--raw-field",
            "threadId=\(threadID)",
            "--raw-field",
            "query=\(reviewThreadMutation(for: action))"
        ])
    }

    private static func reviewThreadMutation(for action: String) -> String {
        let mutation = action == "resolve" ? "resolveReviewThread" : "unresolveReviewThread"
        let nonNull = "\u{21}"
        let signature = "mutation($threadId: ID\(nonNull))"
        let operation = "\(mutation)(input: {threadId: $threadId})"
        return "\(signature) { \(operation) { thread { id isResolved } } }"
    }

    private static func pullRequestNumberCommand(selector: String?) throws -> String {
        try WorkspaceRemoteGitHubPullRequestCommandSupport.pullRequestViewCommand(
            selector: selector,
            json: "number",
            jq: ".number"
        )
    }

    private static func pullRequestNumberAndHeadCommand(selector: String?) throws -> String {
        try WorkspaceRemoteGitHubPullRequestCommandSupport.pullRequestViewCommand(
            selector: selector,
            json: "number,headRefOid",
            jq: ".number + \" \" + .headRefOid"
        )
    }

    private static func quoted(_ argument: String) -> String {
        WorkspaceRemoteGitHubPullRequestCommandSupport.quoted(argument)
    }
}
