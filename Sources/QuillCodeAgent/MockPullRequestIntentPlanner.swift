import Foundation
import QuillCodeCore
import QuillCodeTools

enum MockPullRequestIntentPlanner {
    static func toolCall(for request: String, lowercasedRequest: String) -> ToolCall? {
        if isPullRequestListRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestList.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.listArguments(from: request))
            )
        }

        if isPullRequestCheckoutRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestCheckout.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.selectorArguments(from: request))
            )
        }

        if isPullRequestReviewerRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestReviewers.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.reviewerArguments(from: request))
            )
        }

        if isPullRequestLabelRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestLabels.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.labelArguments(from: request))
            )
        }

        if isPullRequestMergeRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestMerge.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.mergeArguments(from: request))
            )
        }

        if isPullRequestLifecycleRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestLifecycle.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.lifecycleArguments(from: request))
            )
        }

        if isPullRequestReviewActionRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestReview.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.reviewArguments(from: request))
            )
        }

        if isPullRequestCommentRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestComment.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.commentArguments(from: request))
            )
        }

        if isPullRequestChecksRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestChecks.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.selectorArguments(from: request))
            )
        }

        if isPullRequestViewRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestView.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.selectorArguments(from: request))
            )
        }

        if isPullRequestRequest(lowercasedRequest) {
            return ToolCall(
                name: ToolDefinition.gitPullRequestCreate.name,
                argumentsJSON: ToolArguments.json(MockPullRequestArgumentExtractor.createArguments(from: request))
            )
        }

        return nil
    }

    static func isPullRequestListRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        guard mentionsPullRequest(lowercasedRequest, tokens: tokens) else { return false }
        return tokens.contains("list")
            || tokens.contains("ls")
            || tokens.contains("browse")
            || tokens.contains("find")
            || lowercasedRequest.contains("show prs")
            || lowercasedRequest.contains("open prs")
    }

    static func isPullRequestRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        let creationTerms = tokens.contains("create")
            || tokens.contains("submit")
            || tokens.contains("new")
            || (tokens.contains("open") && !tokens.contains("current") && !tokens.contains("existing"))
        return mentionsPullRequest(lowercasedRequest, tokens: tokens) && creationTerms
    }

    static func isPullRequestChecksRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        let checkTerms = tokens.contains("check")
            || tokens.contains("checks")
            || tokens.contains("ci")
            || tokens.contains("status")
        return mentionsPullRequest(lowercasedRequest, tokens: tokens) && checkTerms
    }

    static func isPullRequestCommentRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        let commentTerms = tokens.contains("comment")
            || tokens.contains("comments")
            || tokens.contains("reply")
        let readTerms = tokens.contains("show")
            || tokens.contains("view")
            || tokens.contains("read")
            || tokens.contains("inspect")
            || tokens.contains("summarize")
        return mentionsPullRequest(lowercasedRequest, tokens: tokens) && commentTerms && !readTerms
    }

    static func isPullRequestMergeRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        guard mentionsPullRequest(lowercasedRequest, tokens: tokens) else { return false }
        return tokens.contains("merge")
            || tokens.contains("automerge")
            || lowercasedRequest.contains("auto merge")
            || lowercasedRequest.contains("merge train")
    }

    static func isPullRequestLifecycleRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        guard mentionsPullRequest(lowercasedRequest, tokens: tokens) else { return false }
        return tokens.contains("close")
            || tokens.contains("closed")
            || tokens.contains("reopen")
            || lowercasedRequest.contains("re-open")
    }

    static func isPullRequestCheckoutRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        guard mentionsPullRequest(lowercasedRequest, tokens: tokens) else { return false }
        return tokens.contains("checkout")
            || lowercasedRequest.contains("check out")
            || tokens.contains("switch")
            || tokens.contains("open")
    }

    static func isPullRequestReviewActionRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        guard mentionsPullRequest(lowercasedRequest, tokens: tokens) else { return false }
        if tokens.contains("approve") || tokens.contains("approved") {
            return true
        }
        if lowercasedRequest.contains("request changes")
            || lowercasedRequest.contains("needs changes")
            || lowercasedRequest.contains("reject pr") {
            return true
        }
        return (tokens.contains("submit") || tokens.contains("leave") || tokens.contains("add"))
            && tokens.contains("review")
    }

    static func isPullRequestReviewerRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        guard mentionsPullRequest(lowercasedRequest, tokens: tokens) else { return false }
        if lowercasedRequest.contains("request review from")
            || lowercasedRequest.contains("request reviewer")
            || lowercasedRequest.contains("request reviewers")
            || lowercasedRequest.contains("add reviewer")
            || lowercasedRequest.contains("add reviewers")
            || lowercasedRequest.contains("re-request reviewer")
            || lowercasedRequest.contains("remove reviewer")
            || lowercasedRequest.contains("remove reviewers") {
            return true
        }
        return (tokens.contains("reviewer") || tokens.contains("reviewers"))
            && (tokens.contains("request") || tokens.contains("add") || tokens.contains("remove"))
    }

    static func isPullRequestLabelRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        guard mentionsPullRequest(lowercasedRequest, tokens: tokens) else { return false }
        if lowercasedRequest.contains("add label")
            || lowercasedRequest.contains("add labels")
            || lowercasedRequest.contains("remove label")
            || lowercasedRequest.contains("remove labels")
            || lowercasedRequest.contains("label this")
            || lowercasedRequest.contains("label the pr")
            || lowercasedRequest.contains("label pr")
            || lowercasedRequest.contains("unlabel") {
            return true
        }
        return (tokens.contains("label") || tokens.contains("labels"))
            && (tokens.contains("add") || tokens.contains("remove") || tokens.contains("set"))
    }

    static func isPullRequestViewRequest(_ lowercasedRequest: String) -> Bool {
        let tokens = tokenizeWords(lowercasedRequest)
        let viewTerms = tokens.contains("view")
            || tokens.contains("show")
            || tokens.contains("inspect")
            || tokens.contains("current")
            || tokens.contains("comments")
            || tokens.contains("reviews")
            || tokens.contains("review")
        let createTerms = tokens.contains("create")
            || tokens.contains("submit")
            || tokens.contains("new")
        return mentionsPullRequest(lowercasedRequest, tokens: tokens) && viewTerms && !createTerms
    }

    private static func mentionsPullRequest(_ lowercasedRequest: String, tokens: [String]) -> Bool {
        lowercasedRequest.contains("pull request")
            || tokens.contains("pr")
            || tokens.contains("prs")
    }

    private static func tokenizeWords(_ lowercasedRequest: String) -> [String] {
        lowercasedRequest
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
