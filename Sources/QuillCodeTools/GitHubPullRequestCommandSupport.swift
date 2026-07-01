import Foundation
import QuillCodeCore

enum GitHubPullRequestCommandSupport {
    static func appendSelector(to arguments: inout [String], selector: String?) throws {
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
    }

    static func addURLArtifacts(to result: ToolResult) -> ToolResult {
        guard result.ok else { return result }
        return ToolResult(
            ok: true,
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            artifacts: GitHubPullRequestOutputParser.extractURLs(from: result.stdout)
        )
    }

    static func repositoryOwnerAndName(_ nameWithOwner: String) throws -> (owner: String, name: String) {
        let parts = nameWithOwner.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw GitToolError.invalidPullRequestSelector(nameWithOwner)
        }
        return (parts[0], parts[1])
    }
}
