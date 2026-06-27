import Foundation

struct GitHubPullRequestMetadata: Decodable, Equatable, Sendable {
    var number: Int
    var headRefOid: String
}

struct GitHubRepositoryMetadata: Decodable, Equatable, Sendable {
    var nameWithOwner: String
}

struct GitHubPullRequestMetadataResolver: Sendable {
    private let runner: GitProcessRunner

    init(runner: GitProcessRunner) {
        self.runner = runner
    }

    func pullRequest(selector: String?, cwd: URL) throws -> GitHubPullRequestMetadata {
        var arguments = ["pr", "view"]
        if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
            arguments.append(selector)
        }
        arguments += ["--json", "number,headRefOid"]
        let result = runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
        guard result.ok else {
            throw GitHubPullRequestMetadataError.commandFailed(result.error ?? result.stderr)
        }
        return try decodePullRequestMetadata(from: result.stdout)
    }

    func repository(cwd: URL) throws -> GitHubRepositoryMetadata {
        let result = runner.runGitHub(
            ["repo", "view", "--json", "nameWithOwner"],
            cwd: cwd,
            timeoutSeconds: 45
        )
        guard result.ok else {
            throw GitHubPullRequestMetadataError.commandFailed(result.error ?? result.stderr)
        }
        return try decodeRepositoryMetadata(from: result.stdout)
    }

    private func decodePullRequestMetadata(from output: String) throws -> GitHubPullRequestMetadata {
        guard let data = output.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(GitHubPullRequestMetadata.self, from: data),
              metadata.number > 0,
              !metadata.headRefOid.isEmpty
        else {
            throw GitHubPullRequestMetadataError.invalidPullRequestMetadata(trimmedOutput(output))
        }
        return metadata
    }

    private func decodeRepositoryMetadata(from output: String) throws -> GitHubRepositoryMetadata {
        guard let data = output.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(GitHubRepositoryMetadata.self, from: data),
              metadata.nameWithOwner.range(
                of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#,
                options: .regularExpression
              ) != nil
        else {
            throw GitHubPullRequestMetadataError.invalidRepositoryMetadata(trimmedOutput(output))
        }
        return metadata
    }

    private func trimmedOutput(_ output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum GitHubPullRequestMetadataError: Error, CustomStringConvertible, Equatable {
    case commandFailed(String)
    case invalidPullRequestMetadata(String)
    case invalidRepositoryMetadata(String)

    var description: String {
        switch self {
        case .commandFailed(let message):
            return "Failed to resolve GitHub pull request metadata: \(message)"
        case .invalidPullRequestMetadata(let output):
            return "GitHub pull request metadata response was invalid: \(output)"
        case .invalidRepositoryMetadata(let output):
            return "GitHub repository metadata response was invalid: \(output)"
        }
    }
}
