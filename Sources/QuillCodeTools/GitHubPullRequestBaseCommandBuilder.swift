import Foundation

enum GitHubPullRequestBaseCommandBuilder {
    static func create(
        title: String?,
        body: String?,
        base: String?,
        head: String?,
        draft: Bool,
        fill: Bool
    ) throws -> [String] {
        let trimmedTitle = GitInputValidator.trimmedNonEmpty(title)
        guard fill || trimmedTitle != nil else {
            throw GitToolError.emptyPullRequestTitle
        }

        var arguments = ["pr", "create"]
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
        return arguments
    }

    static func view(selector: String?) throws -> [String] {
        var arguments = ["pr", "view"]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments.append("--comments")
        return arguments
    }

    static func checks(selector: String?) throws -> [String] {
        try selectorCommand(subcommand: "checks", selector: selector)
    }

    static func diff(selector: String?) throws -> [String] {
        try selectorCommand(subcommand: "diff", selector: selector)
    }

    static func checkout(selector: String?, branch: String?) throws -> [String] {
        var arguments = ["pr", "checkout"]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        if let branch = GitInputValidator.trimmedNonEmpty(branch) {
            arguments += ["--branch", try GitInputValidator.safeName(branch)]
        }
        return arguments
    }

    private static func selectorCommand(subcommand: String, selector: String?) throws -> [String] {
        var arguments = ["pr", subcommand]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        return arguments
    }
}
