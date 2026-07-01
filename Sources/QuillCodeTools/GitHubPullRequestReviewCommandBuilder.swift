import Foundation

enum GitHubPullRequestReviewCommandBuilder {
    static func review(
        selector: String?,
        action: String,
        body: String?
    ) throws -> [String] {
        let flag = try GitHubPullRequestInputValidator.safeReviewFlag(action)
        let body = GitInputValidator.trimmedNonEmpty(body)
        guard flag == "--approve" || body != nil else {
            throw GitToolError.emptyPullRequestReviewBody
        }

        var arguments = ["pr", "review"]
        try GitHubPullRequestCommandSupport.appendSelector(to: &arguments, selector: selector)
        arguments.append(flag)
        if let body {
            arguments += ["--body", body]
        }
        return arguments
    }

    static func reviewComment(
        cwd: URL,
        path: String,
        line: Int,
        side: String?,
        body: String,
        startLine: Int?,
        startSide: String?,
        pullRequest: GitHubPullRequestMetadata,
        repository: GitHubRepositoryMetadata
    ) throws -> [String] {
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
        return arguments
    }

    static func reviewReply(
        commentID: Int,
        body: String,
        pullRequest: GitHubPullRequestMetadata,
        repository: GitHubRepositoryMetadata
    ) throws -> [String] {
        guard let body = GitInputValidator.trimmedNonEmpty(body) else {
            throw GitToolError.emptyPullRequestComment
        }
        let commentID = try GitHubPullRequestInputValidator.safeReviewCommentID(commentID)

        return [
            "api",
            "repos/\(repository.nameWithOwner)/pulls/\(pullRequest.number)/comments/\(commentID)/replies",
            "--raw-field",
            "body=\(body)"
        ]
    }

    static func reviewThreads(
        pullRequest: GitHubPullRequestMetadata,
        repository: GitHubRepositoryMetadata
    ) throws -> [String] {
        let (owner, name) = try GitHubPullRequestCommandSupport.repositoryOwnerAndName(repository.nameWithOwner)
        return [
            "api",
            "graphql",
            "--raw-field",
            "owner=\(owner)",
            "--raw-field",
            "name=\(name)",
            "--field",
            "number=\(pullRequest.number)",
            "--raw-field",
            "query=\(GitHubPullRequestReviewThreadsQuery.graphql)"
        ]
    }

    static func reviewThread(threadID: String, action: String) throws -> [String] {
        let threadID = try GitHubPullRequestInputValidator.safeReviewThreadID(threadID)
        let action = try GitHubPullRequestInputValidator.safeReviewThreadAction(action)
        return [
            "api",
            "graphql",
            "--raw-field",
            "threadId=\(threadID)",
            "--raw-field",
            "query=\(reviewThreadMutation(for: action))"
        ]
    }

    private static func reviewThreadMutation(for action: String) -> String {
        let mutation = action == "resolve" ? "resolveReviewThread" : "unresolveReviewThread"
        let nonNull = "\u{21}"
        return "mutation($threadId: ID\(nonNull)) { \(mutation)(input: {threadId: $threadId}) { thread { id isResolved } } }"
    }
}
