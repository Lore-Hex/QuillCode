import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestCommandSupport {
    static func appendSelector(to arguments: inout [String], selector: String?) throws {
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
    }

    static func command(_ arguments: [String]) -> String {
        WorkspaceRemoteShellCommandFormatter.command(arguments)
    }

    static func quoted(_ argument: String) -> String {
        WorkspaceRemoteShellCommandFormatter.shellSingleQuoted(argument)
    }

    static func pullRequestViewCommand(
        selector: String?,
        json: String,
        jq: String
    ) throws -> String {
        var arguments = ["gh", "pr", "view"]
        try appendSelector(to: &arguments, selector: selector)
        arguments += ["--json", json, "--jq", jq]
        return command(arguments)
    }

    static func repoNameWithOwnerCommand() -> String {
        command([
            "gh",
            "repo",
            "view",
            "--json",
            "nameWithOwner",
            "--jq",
            ".nameWithOwner"
        ])
    }
}
