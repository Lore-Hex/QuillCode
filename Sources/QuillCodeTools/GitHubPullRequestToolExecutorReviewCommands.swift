import Foundation
import QuillCodeCore

public extension GitHubPullRequestToolExecutor {
    func review(
        cwd: URL,
        selector: String? = nil,
        action: String,
        body: String? = nil
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60, addURLArtifacts: true) {
            try GitHubPullRequestReviewCommandBuilder.review(
                selector: selector,
                action: action,
                body: body
            )
        }
    }

    func reviewComment(
        cwd: URL,
        selector: String? = nil,
        path: String,
        line: Int,
        side: String? = nil,
        body: String,
        startLine: Int? = nil,
        startSide: String? = nil
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60, addURLArtifacts: true) {
            let pullRequest = try metadataResolver.pullRequest(selector: selector, cwd: cwd)
            let repository = try metadataResolver.repository(cwd: cwd)
            return try GitHubPullRequestReviewCommandBuilder.reviewComment(
                cwd: cwd,
                path: path,
                line: line,
                side: side,
                body: body,
                startLine: startLine,
                startSide: startSide,
                pullRequest: pullRequest,
                repository: repository
            )
        }
    }

    func reviewReply(
        cwd: URL,
        selector: String? = nil,
        commentID: Int,
        body: String
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60, addURLArtifacts: true) {
            let pullRequest = try metadataResolver.pullRequest(selector: selector, cwd: cwd)
            let repository = try metadataResolver.repository(cwd: cwd)
            return try GitHubPullRequestReviewCommandBuilder.reviewReply(
                commentID: commentID,
                body: body,
                pullRequest: pullRequest,
                repository: repository
            )
        }
    }

    func reviewThreads(cwd: URL, selector: String? = nil) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60) {
            let pullRequest = try metadataResolver.pullRequest(selector: selector, cwd: cwd)
            let repository = try metadataResolver.repository(cwd: cwd)
            return try GitHubPullRequestReviewCommandBuilder.reviewThreads(
                pullRequest: pullRequest,
                repository: repository
            )
        }
    }

    func reviewThread(
        cwd: URL,
        threadID: String,
        action: String
    ) -> ToolResult {
        runGitHub(cwd: cwd, timeoutSeconds: 60) {
            try GitHubPullRequestReviewCommandBuilder.reviewThread(threadID: threadID, action: action)
        }
    }
}
