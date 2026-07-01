import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestReviewThreadCommandBuilder {
    static let toolNames: Set<String> = [
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name,
        ToolDefinition.gitPullRequestReviewThreads.name,
        ToolDefinition.gitPullRequestReviewThread.name
    ]

    static let urlArtifactToolNames: Set<String> = [
        ToolDefinition.gitPullRequestReviewComment.name,
        ToolDefinition.gitPullRequestReviewReply.name
    ]

    static func command(for call: ToolCall, arguments args: ToolArguments) throws -> String {
        switch call.name {
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

        return [
            "pr_data=$(\(try support.pullRequestNumberAndHeadOIDCommand(selector: selector)))",
            "pr_number=${pr_data%% *}",
            "head_oid=${pr_data#* }",
            "repo=$(\(support.repositoryNameWithOwnerCommand()))",
            "gh api \"repos/${repo}/pulls/${pr_number}/comments\" \(apiFields.joined(separator: " "))"
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
        let endpoint = "\"repos/${repo}/pulls/${pr_number}/comments/\(commentID)/replies\""

        return [
            "pr_number=$(\(try support.pullRequestNumberCommand(selector: selector)))",
            "repo=$(\(support.repositoryNameWithOwnerCommand()))",
            "gh api \(endpoint) \(quoted("--raw-field")) \(quoted("body=\(body)"))"
        ].joined(separator: " && ")
    }

    private static func reviewThreads(selector: String?) throws -> String {
        let queryField = quoted("query=\(GitHubPullRequestReviewThreadsQuery.graphql)")
        let graphqlArguments = [
            quoted("--raw-field"), "\"owner=${owner}\"",
            quoted("--raw-field"), "\"name=${name}\"",
            quoted("--field"), "\"number=${pr_number}\"",
            quoted("--raw-field"), queryField
        ].joined(separator: " ")

        return [
            "pr_number=$(\(try support.pullRequestNumberCommand(selector: selector)))",
            "repo=$(\(support.repositoryNameWithOwnerCommand()))",
            "owner=${repo%%/*}",
            "name=${repo#*/}",
            "gh api graphql \(graphqlArguments)"
        ].joined(separator: " && ")
    }

    private static func reviewThread(
        threadID: String,
        action: String
    ) throws -> String {
        let threadID = try GitHubPullRequestInputValidator.safeReviewThreadID(threadID)
        let action = try GitHubPullRequestInputValidator.safeReviewThreadAction(action)
        return command([
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
        return [
            "mutation($threadId: ID\(nonNull)) {",
            "\(mutation)(input: {threadId: $threadId}) { thread { id isResolved } }",
            "}"
        ].joined(separator: " ")
    }

    private static var support: WorkspaceRemoteGitHubPullRequestCommandSupport.Type {
        WorkspaceRemoteGitHubPullRequestCommandSupport.self
    }

    private static func command(_ arguments: [String]) -> String {
        support.command(arguments)
    }

    private static func quoted(_ argument: String) -> String {
        support.quoted(argument)
    }
}
