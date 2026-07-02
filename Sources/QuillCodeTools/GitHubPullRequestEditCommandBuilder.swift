import Foundation

enum GitHubPullRequestEditCommandBuilder {
    static func reviewers(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> [String] {
        let reviewersToAdd = try GitHubPullRequestInputValidator.safeReviewers(add)
        let reviewersToRemove = try GitHubPullRequestInputValidator.safeReviewers(remove)
        guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestReviewers
        }

        var arguments = ["pr", "edit"]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        if !reviewersToAdd.isEmpty {
            arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
        }
        if !reviewersToRemove.isEmpty {
            arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
        }
        return arguments
    }

    static func labels(
        selector: String?,
        add: [String]?,
        remove: [String]?
    ) throws -> [String] {
        let labelsToAdd = try GitHubPullRequestInputValidator.safeLabels(add)
        let labelsToRemove = try GitHubPullRequestInputValidator.safeLabels(remove)
        guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
            throw GitToolError.emptyPullRequestLabels
        }

        var arguments = ["pr", "edit"]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        if !labelsToAdd.isEmpty {
            arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
        }
        if !labelsToRemove.isEmpty {
            arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
        }
        return arguments
    }

    static func comment(selector: String?, body: String) throws -> [String] {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }

        var arguments = ["pr", "comment"]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments += ["--body", body]
        return arguments
    }

    static func lifecycle(selector: String?, action: String) throws -> [String] {
        let safeAction = try GitHubPullRequestInputValidator.safeLifecycleAction(action)
        var arguments = ["pr", safeAction]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        return arguments
    }
}
