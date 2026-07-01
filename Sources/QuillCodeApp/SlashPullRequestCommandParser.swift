import Foundation
import QuillCodeCore
import QuillCodeTools

enum SlashPullRequestCommandParser {
    static func parse(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawSubcommand = parts.first?.lowercased() else {
            return .workspaceCommand("git-pr-create")
        }
        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let subcommand = rawSubcommand.replacingOccurrences(of: "-", with: "_")

        switch subcommand {
        case "create", "new", "open":
            let normalizedRest = rest.lowercased()
            if normalizedRest == "--fill" || normalizedRest == "fill" {
                return .workspaceCommand("git-pr-fill")
            }
            return .workspaceCommand("git-pr-create")
        case "fill", "autofill":
            return .workspaceCommand("git-pr-fill")
        case "view", "show", "inspect", "comments":
            return pullRequestTool(.gitPullRequestView, selector: rest)
        case "checks", "ci", "status":
            return pullRequestTool(.gitPullRequestChecks, selector: rest)
        case "diff", "changes":
            return pullRequestTool(.gitPullRequestDiff, selector: rest)
        case "checkout", "switch":
            guard !rest.isEmpty else {
                return .workspaceCommand("git-pr-checkout")
            }
            return pullRequestTool(.gitPullRequestCheckout, selector: rest)
        case "comment", "reply":
            let parsed = selectorAndBody(from: rest)
            guard !parsed.body.isEmpty else {
                return .invalid("Usage: /pr comment OptionalPRSelector comment text")
            }
            return pullRequestTool(
                .gitPullRequestComment,
                arguments: compact(["selector": parsed.selector, "body": parsed.body])
            )
        case "review":
            return parseReview(rest)
        case "review_comment", "line_comment", "inline_comment", "inline":
            return parseReviewComment(rest)
        case "review_reply", "inline_reply", "reply_comment":
            return parseReviewReply(rest)
        case "review_threads", "threads", "review_thread_list", "thread_list", "list_threads":
            return pullRequestTool(.gitPullRequestReviewThreads, selector: rest)
        case "review_thread", "thread":
            return parseReviewThread(rest)
        case "resolve_thread", "resolve_review_thread":
            return parseReviewThreadID(rest, action: "resolve")
        case "unresolve_thread", "unresolve_review_thread", "reopen_thread":
            return parseReviewThreadID(rest, action: "unresolve")
        case "approve", "approved":
            let parsed = selectorAndBody(from: rest)
            return pullRequestTool(
                .gitPullRequestReview,
                arguments: compact(["selector": parsed.selector, "action": "approve", "body": parsed.body])
            )
        case "request_changes":
            let parsed = selectorAndBody(from: rest)
            guard !parsed.body.isEmpty else {
                return .invalid("Usage: /pr review request_changes OptionalPRSelector review body")
            }
            return pullRequestTool(
                .gitPullRequestReview,
                arguments: compact(["selector": parsed.selector, "action": "request_changes", "body": parsed.body])
            )
        case "reviewers", "reviewer":
            return parseReviewers(rest)
        case "labels", "label":
            return parseLabels(rest)
        case "merge", "automerge", "auto_merge":
            return parseMerge(rest, autoByDefault: subcommand != "merge")
        default:
            return .invalid("Unknown pull request command '\(rawSubcommand)'. Use create, fill, view, checks, diff, checkout, comment, review, review-comment, review-reply, review-threads, review-thread, reviewers, labels, or merge.")
        }
    }
}
