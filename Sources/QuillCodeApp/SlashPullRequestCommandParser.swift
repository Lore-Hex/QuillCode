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
            return .workspaceCommand("git-pr-create")
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
            return .invalid("Unknown pull request command '\(rawSubcommand)'. Use create, view, checks, diff, checkout, comment, review, review-comment, review-reply, review-threads, review-thread, reviewers, labels, or merge.")
        }
    }

    private static func parseReview(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawAction = parts.first?.lowercased() else {
            return .invalid("Usage: /pr review approve, /pr review comment body, or /pr review request_changes body")
        }
        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let action = rawAction.replacingOccurrences(of: "-", with: "_")
        let normalizedAction: String
        switch action {
        case "approve", "approved":
            normalizedAction = "approve"
        case "comment", "comments":
            normalizedAction = "comment"
        case "request_changes", "request_change":
            normalizedAction = "request_changes"
        default:
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

    private static func parseReviewComment(_ argument: String) -> SlashCommand {
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

    private static func parseReviewReply(_ argument: String) -> SlashCommand {
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

    private static func parseReviewThread(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawAction = parts.first?.lowercased(),
              parts.count > 1
        else {
            return .invalid("Usage: /pr review-thread resolve threadId or /pr review-thread unresolve threadId")
        }
        let action = rawAction.replacingOccurrences(of: "-", with: "_")
        switch action {
        case "resolve", "resolved":
            return parseReviewThreadID(String(parts[1]), action: "resolve")
        case "unresolve", "unresolved", "reopen", "open":
            return parseReviewThreadID(String(parts[1]), action: "unresolve")
        default:
            return .invalid("Unknown pull request review thread action '\(rawAction)'. Use resolve or unresolve.")
        }
    }

    private static func parseReviewThreadID(_ argument: String, action: String) -> SlashCommand {
        let threadID = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !threadID.isEmpty else {
            return .invalid("Usage: /pr \(action)-thread threadId")
        }
        return pullRequestTool(
            .gitPullRequestReviewThread,
            arguments: ["threadId": threadID, "action": action]
        )
    }

    private static func parseReviewers(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawAction = parts.first?.lowercased(),
              ["add", "request", "remove", "delete"].contains(rawAction)
        else {
            return .invalid("Usage: /pr reviewers add alice bob or /pr reviewers remove alice")
        }
        let reviewers = parts.count > 1
            ? String(parts[1]).split(whereSeparator: \.isWhitespace).map(String.init)
            : []
        guard !reviewers.isEmpty else {
            return .invalid("Usage: /pr reviewers add alice bob or /pr reviewers remove alice")
        }
        let key = (rawAction == "remove" || rawAction == "delete") ? "remove" : "add"
        return pullRequestTool(.gitPullRequestReviewers, arguments: [key: reviewers])
    }

    private static func parseLabels(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let rawAction = parts.first?.lowercased(),
              ["add", "apply", "remove", "delete"].contains(rawAction)
        else {
            return .invalid("Usage: /pr labels add label[, label] or /pr labels remove label")
        }
        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let parsed = selectorAndBody(from: rest)
        let labels = pullRequestLabels(from: parsed.body)
        guard !labels.isEmpty else {
            return .invalid("Usage: /pr labels add label[, label] or /pr labels remove label")
        }
        let key = (rawAction == "remove" || rawAction == "delete") ? "remove" : "add"
        return pullRequestTool(
            .gitPullRequestLabels,
            arguments: compact(["selector": parsed.selector, key: labels])
        )
    }

    private static func parseMerge(_ argument: String, autoByDefault: Bool) -> SlashCommand {
        let tokens = argument.split(whereSeparator: \.isWhitespace).map(String.init)
        var selector: String?
        var method: String?
        var auto = autoByDefault
        var deleteBranch = false

        for token in tokens {
            let normalized = token.lowercased().replacingOccurrences(of: "-", with: "_")
            switch normalized {
            case "squash", "merge", "rebase":
                method = normalized
            case "auto", "automerge", "auto_merge":
                auto = true
            case "delete_branch", "delete":
                deleteBranch = true
            default:
                if selector == nil {
                    selector = normalizedPullRequestSelector(token)
                }
            }
        }

        return pullRequestTool(
            .gitPullRequestMerge,
            arguments: compact([
                "selector": selector,
                "method": method ?? "squash",
                "auto": auto,
                "deleteBranch": deleteBranch
            ])
        )
    }

    private static func selectorAndBody(from argument: String) -> (selector: String?, body: String) {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace).first else {
            return (nil, "")
        }
        let firstToken = String(first)
        guard looksLikePullRequestSelector(firstToken) else {
            return (nil, trimmed)
        }
        let bodyStart = trimmed.index(trimmed.startIndex, offsetBy: firstToken.count)
        let body = String(trimmed[bodyStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (normalizedPullRequestSelector(firstToken), body)
    }

    private static func pullRequestLabels(from body: String) -> [String] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.contains(",") {
            return trimmed.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func looksLikePullRequestSelector(_ token: String) -> Bool {
        let normalized = normalizedPullRequestSelector(token)
        guard !normalized.isEmpty else { return false }
        if normalized.allSatisfy(\.isNumber) {
            return true
        }
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return true
        }
        return normalized.contains("/") && !normalized.hasPrefix("-")
    }

    private static func normalizedPullRequestSelector(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespacesAndNewlines))
    }

    private static func pullRequestTool(_ definition: ToolDefinition, selector: String) -> SlashCommand {
        pullRequestTool(definition, arguments: compact(["selector": selector]))
    }

    private static func pullRequestTool(_ definition: ToolDefinition, arguments: [String: Any]) -> SlashCommand {
        .toolCall(ToolCall(name: definition.name, argumentsJSON: ToolArguments.json(arguments)))
    }

    private static func compact(_ values: [String: Any?]) -> [String: Any] {
        values.compactMapValues { value in
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return value
        }
    }
}
