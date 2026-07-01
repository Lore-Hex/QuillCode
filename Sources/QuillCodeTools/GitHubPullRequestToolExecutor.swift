import Foundation
import QuillCodeCore

public struct GitHubPullRequestToolExecutor: Sendable {
    let runner: GitProcessRunner
    let metadataResolver: GitHubPullRequestMetadataResolver

    public init(runner: GitProcessRunner) {
        self.runner = runner
        self.metadataResolver = GitHubPullRequestMetadataResolver(runner: runner)
    }

    public init(githubCLIExecutable: URL?) {
        self.init(runner: GitProcessRunner(githubCLIExecutable: githubCLIExecutable))
    }

    func runGitHub(
        cwd: URL,
        timeoutSeconds: TimeInterval,
        addURLArtifacts: Bool = false,
        arguments makeArguments: () throws -> [String]
    ) -> ToolResult {
        do {
            let result = runner.runGitHub(
                try makeArguments(),
                cwd: cwd,
                timeoutSeconds: timeoutSeconds
            )
            return addURLArtifacts
                ? GitHubPullRequestCommandSupport.addURLArtifacts(to: result)
                : result
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }
}
