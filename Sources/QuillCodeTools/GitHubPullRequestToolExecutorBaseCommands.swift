import Foundation
import QuillCodeCore

public extension GitHubPullRequestToolExecutor {
    func list(cwd: URL, state: String? = nil, limit: Int? = nil) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 45, addURLArtifacts: true) {
            try GitHubPullRequestBaseCommandBuilder.list(state: state, limit: limit)
        }
    }

    func createPullRequest(
        cwd: URL,
        title: String? = nil,
        body: String? = nil,
        base: String? = nil,
        head: String? = nil,
        draft: Bool = false,
        fill: Bool = false
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 120, addURLArtifacts: true) {
            try GitHubPullRequestBaseCommandBuilder.create(
                title: title,
                body: body,
                base: base,
                head: head,
                draft: draft,
                fill: fill
            )
        }
    }

    func view(cwd: URL, selector: String? = nil) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 45, addURLArtifacts: true) {
            try GitHubPullRequestBaseCommandBuilder.view(selector: selector)
        }
    }

    func checks(cwd: URL, selector: String? = nil) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 45) {
            try GitHubPullRequestBaseCommandBuilder.checks(selector: selector)
        }
    }

    func diff(cwd: URL, selector: String? = nil) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 45) {
            try GitHubPullRequestBaseCommandBuilder.diff(selector: selector)
        }
    }

    func checkout(cwd: URL, selector: String? = nil, branch: String? = nil) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 120) {
            try GitHubPullRequestBaseCommandBuilder.checkout(selector: selector, branch: branch)
        }
    }
}
