import Foundation

enum GitHubPullRequestMergeCommandBuilder {
    static func merge(
        selector: String?,
        method: String?,
        auto: Bool,
        deleteBranch: Bool
    ) throws -> [String] {
        var arguments = ["pr", "merge"]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments.append(try GitHubPullRequestInputValidator.safeMergeFlag(method))
        if auto {
            arguments.append("--auto")
        }
        if deleteBranch {
            arguments.append("--delete-branch")
        }
        return arguments
    }
}
