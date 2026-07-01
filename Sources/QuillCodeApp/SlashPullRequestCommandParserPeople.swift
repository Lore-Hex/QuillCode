import Foundation
import QuillCodeTools

extension SlashPullRequestCommandParser {
    static func parseReviewers(_ argument: String) -> SlashCommand {
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

    static func parseLabels(_ argument: String) -> SlashCommand {
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

    static func parseMerge(_ argument: String, autoByDefault: Bool) -> SlashCommand {
        let tokens = argument.split(whereSeparator: \.isWhitespace).map(String.init)
        var selector: String?
        var method: String?
        var auto = autoByDefault
        var deleteBranch = false

        for token in tokens {
            switch token.lowercased().replacingOccurrences(of: "-", with: "_") {
            case "squash", "merge", "rebase":
                method = token.lowercased()
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
}
