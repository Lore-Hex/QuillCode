import QuillCodeCore

public extension ToolDefinition {
    static let gitPullRequestCreate = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.create",
        description: "Create a GitHub pull request for the current project branch using GitHub CLI.",
        parametersJSON: GitToolParameterSchema.object(properties: [
            "base": .string(),
            "body": .string(),
            "draft": .boolean(),
            "fill": .boolean(),
            "head": .string(),
            "title": .string()
        ]),
        risk: .append
    )

    static let gitPullRequestView = pullRequestReadTool(
        name: "host.git.pr.view",
        summary: "View the current or selected GitHub pull request, including comments, using GitHub CLI."
    )

    static let gitPullRequestChecks = pullRequestReadTool(
        name: "host.git.pr.checks",
        summary: "Show CI/check status for the current or selected GitHub pull request using GitHub CLI."
    )

    static let gitPullRequestDiff = pullRequestReadTool(
        name: "host.git.pr.diff",
        summary: "Show the unified diff for the current or selected GitHub pull request using GitHub CLI."
    )

    static let gitPullRequestCheckout = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.checkout",
        description: GitPullRequestDefinitionFactory.described(
            "Check out the current or selected GitHub pull request branch using GitHub CLI."
        ),
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(extra: [
            "branch": .string(description: "Optional local branch name to use for the checkout.")
        ]),
        risk: .append
    )
}

private func pullRequestReadTool(name: String, summary: String) -> ToolDefinition {
    GitPullRequestDefinitionFactory.tool(
        name: name,
        description: GitPullRequestDefinitionFactory.described(summary),
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(),
        risk: .read
    )
}
