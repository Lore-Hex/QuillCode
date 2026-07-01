import Foundation
import QuillCodeTools

extension SlashPullRequestCommandParser {
    static func parseReview(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawAction = parts.first?.lowercased() else {
            return .invalid("Usage: /pr review approve, /pr review comment body, or /pr review request_changes body")
        }
        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        guard let normalizedAction = normalizedReviewAction(rawAction) else {
            return .invalid("Unknown pull request review action '\(rawAction)'. Use approve, comment, or request_changes.")
        }

        let parsed = selectorAndBody(from: rest)
        if normalizedAction != "approve", parsed.body.isEmpty {
            return .invalid("Usage: /pr review \(normalizedAction) OptionalPRSelector review body")
        }
        return pullRequestTool(
            .gitPullRequestReview,
            arguments: compact(["selector": parsed.selector, "action": normalizedAction, "body": parsed.body])
        )
    }

    static func parseReviewComment(_ argument: String) -> SlashCommand {
        let selectorTokens = argument.split(maxSplits: 3, whereSeparator: \.isWhitespace).map(String.init)
        let hasSelector = selectorTokens.count >= 4
            && looksLikePullRequestSelector(selectorTokens[0])
            && Int(selectorTokens[2]) != nil
        let tokens = hasSelector
            ? selectorTokens
            : argument.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 3 else {
            return .invalid("Usage: /pr review-comment OptionalPRSelector path line comment body")
        }

        let selector = hasSelector ? normalizedPullRequestSelector(tokens[0]) : nil
        let pathIndex = hasSelector ? 1 : 0
        let lineIndex = pathIndex + 1
        let bodyIndex = pathIndex + 2
        guard tokens.indices.contains(bodyIndex),
              let line = Int(tokens[lineIndex])
        else {
            return .invalid("Usage: /pr review-comment OptionalPRSelector path line comment body")
        }

        return pullRequestTool(
            .gitPullRequestReviewComment,
            arguments: compact([
                "selector": selector,
                "path": tokens[pathIndex],
                "line": line,
                "body": tokens[bodyIndex]
            ])
        )
    }

    static func parseReviewReply(_ argument: String) -> SlashCommand {
        let selectorTokens = argument.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
        let hasSelector = selectorTokens.count >= 3
            && looksLikePullRequestSelector(selectorTokens[0])
            && Int(selectorTokens[1]) != nil
        let tokens = hasSelector
            ? selectorTokens
            : argument.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else {
            return .invalid("Usage: /pr review-reply OptionalPRSelector commentId reply body")
        }

        let selector = hasSelector ? normalizedPullRequestSelector(tokens[0]) : nil
        let commentIDIndex = hasSelector ? 1 : 0
        let bodyIndex = commentIDIndex + 1
        guard tokens.indices.contains(bodyIndex),
              let commentID = Int(tokens[commentIDIndex]),
              !tokens[bodyIndex].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .invalid("Usage: /pr review-reply OptionalPRSelector commentId reply body")
        }

        return pullRequestTool(
            .gitPullRequestReviewReply,
            arguments: compact([
                "selector": selector,
                "commentId": commentID,
                "body": tokens[bodyIndex]
            ])
        )
    }

    private static func normalizedReviewAction(_ rawAction: String) -> String? {
        switch rawAction.replacingOccurrences(of: "-", with: "_") {
        case "approve", "approved":
            return "approve"
        case "comment", "comments":
            return "comment"
        case "request_changes", "request_change":
            return "request_changes"
        default:
            return nil
        }
    }
}
