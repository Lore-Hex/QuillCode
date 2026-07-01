import QuillCodeCore

public extension ToolDefinition {
    static let gitPullRequestMerge = GitPullRequestDefinitionFactory.tool(
        name: "host.git.pr.merge",
        description: "Merge or enable auto-merge for the current or selected GitHub pull request "
            + "using GitHub CLI. Method must be squash, merge, or rebase.",
        parametersJSON: GitPullRequestDefinitionFactory.selectorParameters(extra: [
            "auto": .boolean(description: "Use GitHub auto-merge when checks are still pending."),
            "deleteBranch": .boolean(
                description: "Delete the pull request branch after merge when supported."
            ),
            "method": .stringEnum(
                ["squash", "merge", "rebase"],
                description: "Merge method. Defaults to squash."
            )
        ]),
        risk: .destructive
    )
}
