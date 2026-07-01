import QuillCodeCore

public extension ToolDefinition {
    static let gitPullRequestReview = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.review",
        description: GitPullRequestDefinitionFactory.described(
            "Submit a GitHub pull request review using GitHub CLI. Action must be approve, comment, or request_changes."
        ),
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(
            extra: [
                "action": .stringEnum(["approve", "comment", "request_changes"]),
                "body": .string(description: "Review body. Required for comment and request_changes.")
            ],
            required: ["action"]
        ),
        risk: .append
    )

    static let gitPullRequestReviewComment = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.review_comment",
        description: GitPullRequestDefinitionFactory.described(
            "Add an inline GitHub pull request review comment to a changed file line."
        ) + " Use path and line from the pull request diff.",
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(
            extra: [
                "body": .string(description: "Inline review comment body."),
                "line": .integer(description: "Target line number in the pull request diff file."),
                "path": .string(description: "Repository-relative file path in the pull request diff."),
                "side": .stringEnum(
                    ["RIGHT", "LEFT"],
                    description: "Diff side for the target line. Defaults to RIGHT."
                ),
                "startLine": .integer(description: "Optional starting line for a multi-line comment."),
                "startSide": .stringEnum(
                    ["RIGHT", "LEFT"],
                    description: "Optional diff side for startLine. Defaults to side."
                )
            ],
            required: ["path", "line", "body"]
        ),
        risk: .append
    )

    static let gitPullRequestReviewReply = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.review_reply",
        description: GitPullRequestDefinitionFactory.described(
            "Reply to an existing inline GitHub pull request review comment thread."
        ) + " Use commentId from the review comment being replied to.",
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(
            extra: [
                "body": .string(description: "Reply body to post."),
                "commentId": .integer(description: "GitHub pull request review comment ID to reply to.")
            ],
            required: ["commentId", "body"]
        ),
        risk: .append
    )

    static let gitPullRequestReviewThreads = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.review_threads",
        description: "List inline GitHub pull request review threads, including GraphQL thread IDs "
            + "and first review comment IDs, for the current or selected pull request.",
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(),
        risk: .read
    )

    static let gitPullRequestReviewThread = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.review_thread",
        description: "Resolve or unresolve an inline GitHub pull request review thread using its GraphQL thread ID.",
        parametersJSON: GitToolParameterSchema.object(
            properties: [
                "action": .stringEnum(
                    ["resolve", "unresolve"],
                    description: "Whether to resolve or unresolve the review thread."
                ),
                "threadId": .string(description: "GitHub GraphQL pull request review thread node ID.")
            ],
            required: ["threadId", "action"]
        ),
        risk: .append
    )
}
