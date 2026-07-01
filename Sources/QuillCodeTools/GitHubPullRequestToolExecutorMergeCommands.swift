import Foundation
import QuillCodeCore

public extension GitHubPullRequestToolExecutor {
    func merge(
        cwd: URL,
        selector: String? = nil,
        method: String? = nil,
        auto: Bool = false,
        deleteBranch: Bool = false
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 120, addURLArtifacts: true) {
            try GitHubPullRequestMergeCommandBuilder.merge(
                selector: selector,
                method: method,
                auto: auto,
                deleteBranch: deleteBranch
            )
        }
    }
}
