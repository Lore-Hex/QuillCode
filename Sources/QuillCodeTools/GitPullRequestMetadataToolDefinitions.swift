import QuillCodeCore

public extension ToolDefinition {
    static let gitPullRequestReviewers = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.reviewers",
        description: GitPullRequestDefinitionFactory.described(
            "Request or remove reviewers on the current or selected GitHub pull request using GitHub CLI."
        ),
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(extra: [
            "add": .stringArray(description: "Reviewer logins or org/team slugs to request."),
            "remove": .stringArray(description: "Reviewer logins or org/team slugs to remove.")
        ]),
        risk: .append
    )

    static let gitPullRequestLabels = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.labels",
        description: GitPullRequestDefinitionFactory.described(
            "Add or remove labels on the current or selected GitHub pull request using GitHub CLI."
        ),
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(extra: [
            "add": .stringArray(description: "Labels to add."),
            "remove": .stringArray(description: "Labels to remove.")
        ]),
        risk: .append
    )

    static let gitPullRequestComment = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.comment",
        description: GitPullRequestDefinitionFactory.described(
            "Add a top-level comment to the current or selected GitHub pull request using GitHub CLI."
        ),
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(
            extra: ["body": .string(description: "Comment body to post.")],
            required: ["body"]
        ),
        risk: .append
    )

    static let gitPullRequestLifecycle = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.lifecycle",
        description: GitPullRequestDefinitionFactory.described(
            "Close or reopen the current or selected GitHub pull request using GitHub CLI."
        ),
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(
            extra: [
                "action": .stringEnum(["close", "reopen"], description: "Lifecycle action to apply.")
            ],
            required: ["action"]
        ),
        risk: .append
    )
}
