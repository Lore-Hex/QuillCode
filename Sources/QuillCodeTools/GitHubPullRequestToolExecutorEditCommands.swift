import Foundation
import QuillCodeCore

public extension GitHubPullRequestToolExecutor {
    func updateReviewers(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60, addURLArtifacts: true) {
            try GitHubPullRequestEditCommandBuilder.reviewers(
                selector: selector,
                add: add,
                remove: remove
            )
        }
    }

    func updateLabels(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60, addURLArtifacts: true) {
            try GitHubPullRequestEditCommandBuilder.labels(selector: selector, add: add, remove: remove)
        }
    }

    func comment(cwd: URL, selector: String? = nil, body: String) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60, addURLArtifacts: true) {
            try GitHubPullRequestEditCommandBuilder.comment(selector: selector, body: body)
        }
    }

    func updateLifecycle(cwd: URL, selector: String? = nil, action: String) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60, addURLArtifacts: true) {
            try GitHubPullRequestEditCommandBuilder.lifecycle(selector: selector, action: action)
        }
    }
}
