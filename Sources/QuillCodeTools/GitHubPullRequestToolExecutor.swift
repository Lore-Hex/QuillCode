import Foundation
import QuillCodeCore

public struct GitHubPullRequestToolExecutor: Sendable {
    private let runner: GitProcessRunner
    private let metadataResolver: GitHubPullRequestMetadataResolver

    public init(runner: GitProcessRunner) {
        self.runner = runner
        self.metadataResolver = GitHubPullRequestMetadataResolver(runner: runner)
    }

    public init(githubCLIExecutable: URL?) {
        self.init(runner: GitProcessRunner(githubCLIExecutable: githubCLIExecutable))
    }

    public func createPullRequest(
        cwd: URL,
        title: String? = nil,
        body: String? = nil,
        base: String? = nil,
        head: String? = nil,
        draft: Bool = false,
        fill: Bool = false
    ) -> ToolResult {
        do {
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

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 120))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func view(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "view"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments.append("--comments")
            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 45))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func checks(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "checks"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            return runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func diff(cwd: URL, selector: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "diff"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            return runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 45)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func checkout(cwd: URL, selector: String? = nil, branch: String? = nil) -> ToolResult {
        do {
            var arguments = ["pr", "checkout"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            if let branch = GitInputValidator.trimmedNonEmpty(branch) {
                arguments += ["--branch", try GitInputValidator.safeName(branch)]
            }
            return runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 120)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func updateReviewers(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        do {
            let reviewersToAdd = try GitHubPullRequestInputValidator.safeReviewers(add)
            let reviewersToRemove = try GitHubPullRequestInputValidator.safeReviewers(remove)
            guard !reviewersToAdd.isEmpty || !reviewersToRemove.isEmpty else {
                throw GitToolError.emptyPullRequestReviewers
            }

            var arguments = ["pr", "edit"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            if !reviewersToAdd.isEmpty {
                arguments += ["--add-reviewer", reviewersToAdd.joined(separator: ",")]
            }
            if !reviewersToRemove.isEmpty {
                arguments += ["--remove-reviewer", reviewersToRemove.joined(separator: ",")]
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func updateLabels(
        cwd: URL,
        selector: String? = nil,
        add: [String]? = nil,
        remove: [String]? = nil
    ) -> ToolResult {
        do {
            let labelsToAdd = try GitHubPullRequestInputValidator.safeLabels(add)
            let labelsToRemove = try GitHubPullRequestInputValidator.safeLabels(remove)
            guard !labelsToAdd.isEmpty || !labelsToRemove.isEmpty else {
                throw GitToolError.emptyPullRequestLabels
            }

            var arguments = ["pr", "edit"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            if !labelsToAdd.isEmpty {
                arguments += ["--add-label", labelsToAdd.joined(separator: ",")]
            }
            if !labelsToRemove.isEmpty {
                arguments += ["--remove-label", labelsToRemove.joined(separator: ",")]
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func comment(cwd: URL, selector: String? = nil, body: String) -> ToolResult {
        do {
            guard let body = GitInputValidator.trimmedNonEmpty(body) else {
                throw GitToolError.emptyPullRequestComment
            }

            var arguments = ["pr", "comment"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments += ["--body", body]

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func review(
        cwd: URL,
        selector: String? = nil,
        action: String,
        body: String? = nil
    ) -> ToolResult {
        do {
            let flag = try GitHubPullRequestInputValidator.safeReviewFlag(action)
            let body = GitInputValidator.trimmedNonEmpty(body)
            guard flag == "--approve" || body != nil else {
                throw GitToolError.emptyPullRequestReviewBody
            }

            var arguments = ["pr", "review"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments.append(flag)
            if let body {
                arguments += ["--body", body]
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func reviewComment(
        cwd: URL,
        selector: String? = nil,
        path: String,
        line: Int,
        side: String? = nil,
        body: String,
        startLine: Int? = nil,
        startSide: String? = nil
    ) -> ToolResult {
        do {
            guard let body = GitInputValidator.trimmedNonEmpty(body) else {
                throw GitToolError.emptyPullRequestComment
            }
            let relativePath = try GitInputValidator.safeRelativePath(path, cwd: cwd)
            guard relativePath != "." else {
                throw GitToolError.emptyPath
            }
            let line = try GitHubPullRequestInputValidator.safeReviewLine(line)
            let startLine = try GitHubPullRequestInputValidator.safeReviewStartLine(startLine, line: line)
            let side = try GitHubPullRequestInputValidator.safeReviewSide(side)
            let resolvedStartSide = try startLine.map { _ in
                try GitHubPullRequestInputValidator.safeReviewSide(startSide ?? side)
            }

            let pullRequest = try metadataResolver.pullRequest(selector: selector, cwd: cwd)
            let repository = try metadataResolver.repository(cwd: cwd)

            var arguments = [
                "api",
                "repos/\(repository.nameWithOwner)/pulls/\(pullRequest.number)/comments",
                "--raw-field",
                "body=\(body)",
                "--raw-field",
                "commit_id=\(pullRequest.headRefOid)",
                "--raw-field",
                "path=\(relativePath)",
                "--field",
                "line=\(line)",
                "--raw-field",
                "side=\(side)"
            ]
            if let startLine {
                arguments += ["--field", "start_line=\(startLine)"]
            }
            if let resolvedStartSide {
                arguments += ["--raw-field", "start_side=\(resolvedStartSide)"]
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func reviewReply(
        cwd: URL,
        selector: String? = nil,
        commentID: Int,
        body: String
    ) -> ToolResult {
        do {
            guard let body = GitInputValidator.trimmedNonEmpty(body) else {
                throw GitToolError.emptyPullRequestComment
            }
            let commentID = try GitHubPullRequestInputValidator.safeReviewCommentID(commentID)
            let pullRequest = try metadataResolver.pullRequest(selector: selector, cwd: cwd)
            let repository = try metadataResolver.repository(cwd: cwd)

            let arguments = [
                "api",
                "repos/\(repository.nameWithOwner)/pulls/\(pullRequest.number)/comments/\(commentID)/replies",
                "--raw-field",
                "body=\(body)"
            ]
            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func reviewThread(
        cwd: URL,
        threadID: String,
        action: String
    ) -> ToolResult {
        do {
            let threadID = try GitHubPullRequestInputValidator.safeReviewThreadID(threadID)
            let action = try GitHubPullRequestInputValidator.safeReviewThreadAction(action)
            let mutation = reviewThreadMutation(for: action)
            let arguments = [
                "api",
                "graphql",
                "--raw-field",
                "threadId=\(threadID)",
                "--raw-field",
                "query=\(mutation)"
            ]
            return runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 60)
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    public func merge(
        cwd: URL,
        selector: String? = nil,
        method: String? = nil,
        auto: Bool = false,
        deleteBranch: Bool = false
    ) -> ToolResult {
        do {
            var arguments = ["pr", "merge"]
            if let selector = try GitHubPullRequestInputValidator.safeSelector(selector) {
                arguments.append(selector)
            }
            arguments.append(try GitHubPullRequestInputValidator.safeMergeFlag(method))
            if auto {
                arguments.append("--auto")
            }
            if deleteBranch {
                arguments.append("--delete-branch")
            }

            return addURLArtifacts(to: runner.runGitHub(arguments, cwd: cwd, timeoutSeconds: 120))
        } catch {
            return ToolResult(ok: false, error: String(describing: error))
        }
    }

    private func reviewThreadMutation(for action: String) -> String {
        let mutation = action == "resolve" ? "resolveReviewThread" : "unresolveReviewThread"
        let nonNull = "\u{21}"
        return "mutation($threadId: ID\(nonNull)) { \(mutation)(input: {threadId: $threadId}) { thread { id isResolved } } }"
    }

    private func addURLArtifacts(to result: ToolResult) -> ToolResult {
        guard result.ok else { return result }
        return ToolResult(
            ok: true,
            stdout: result.stdout,
            stderr: result.stderr,
            exitCode: result.exitCode,
            artifacts: GitHubPullRequestOutputParser.extractURLs(from: result.stdout)
        )
    }
}
