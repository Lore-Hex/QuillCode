import QuillCodeTools

enum WorkspaceRemoteGitHubPullRequestCommandSupport {
    static func command(_ arguments: [String]) -> String {
        arguments.map(WorkspaceTerminalSessionAdapter.shellSingleQuoted).joined(separator: " ")
    }

    static func quoted(_ argument: String) -> String {
        WorkspaceTerminalSessionAdapter.shellSingleQuoted(argument)
    }

    static func pullRequestNumberCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments += ["--json", "number", "--jq", ".number"]
        return command(arguments)
    }

    static func pullRequestNumberAndHeadOIDCommand(selector: String?) throws -> String {
        var arguments = ["gh", "pr", "view"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments += ["--json", "number,headRefOid", "--jq", ".number + \" \" + .headRefOid"]
        return command(arguments)
    }

    static func repositoryNameWithOwnerCommand() -> String {
        command(["gh", "repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"])
    }
}
