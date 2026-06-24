import Foundation
import QuillCodeCore
import QuillCodeTools

enum SlashCommand: Equatable {
    case help
    case status
    case newChat
    case mode(AgentMode)
    case model(String)
    case renameThread(String)
    case renameProject(String)
    case sshProject(String)
    case remember(String)
    case threadFollowUp(String)
    case workspaceSchedule(String)
    case workspaceCommand(String)
    case toolCall(ToolCall)
    case environmentAction(String?)
    case invalid(String)
    case unknown(String)
}

enum SlashCommandParser {
    static func parse(_ input: String) -> SlashCommand? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let commandText = String(trimmed.dropFirst())
        let parts = commandText.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let name = parts.first?.lowercased() else {
            return .help
        }
        let argument = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        switch name {
        case "?", "help":
            return .help
        case "status":
            return .status
        case "new", "new-chat", "newchat":
            return .newChat
        case "compact", "compact-context", "context-compact":
            return .workspaceCommand("compact-context")
        case "follow-up", "followup", "schedule", "remind":
            return argument.isEmpty
                ? .invalid("Usage: /follow-up in 30 minutes, /follow-up tomorrow at 9 AM, or /follow-up daily")
                : .threadFollowUp(argument)
        case "workspace-check", "workspacecheck", "workspace-schedule", "project-check", "repo-check":
            return argument.isEmpty
                ? .invalid("Usage: /workspace-check in 1 hour, /workspace-check tomorrow at 9 AM, or /workspace-check every 2 hours")
                : .workspaceSchedule(argument)
        case "rename", "rename-chat", "title":
            return argument.isEmpty ? .invalid("Usage: /rename New chat title") : .renameThread(argument)
        case "duplicate", "duplicate-chat", "copy-chat":
            return .workspaceCommand("thread-duplicate")
        case "archive", "archive-chat":
            return .workspaceCommand("thread-archive")
        case "unarchive", "unarchive-chat":
            return .workspaceCommand("thread-unarchive")
        case "project":
            return parseProject(argument)
        case "ssh", "remote":
            return argument.isEmpty ? .invalid("Usage: /ssh user@host:/absolute/path") : .sshProject(argument)
        case "terminal", "term", "shell":
            return parseTerminal(argument)
        case "browser", "preview":
            return .workspaceCommand("toggle-browser")
        case "memory", "memories":
            return .workspaceCommand("toggle-memories")
        case "remember":
            return argument.isEmpty ? .workspaceCommand("toggle-memories") : .remember(argument)
        case "worktree", "worktrees", "wt":
            return .workspaceCommand("git-worktree-list")
        case "pr", "pull-request", "pullrequest":
            return parsePullRequest(argument)
        case "env", "environment", "local-env":
            return .environmentAction(argument.isEmpty ? nil : argument)
        case "mode":
            return parseMode(argument)
        case "model":
            guard !argument.isEmpty else {
                return .invalid("Usage: /model /synth or /model provider/model")
            }
            return .model(argument)
        default:
            return .unknown(name)
        }
    }

    private static func parseTerminal(_ argument: String) -> SlashCommand {
        guard !argument.isEmpty else {
            return .workspaceCommand("toggle-terminal")
        }
        switch argument.lowercased() {
        case "clear", "reset":
            return .workspaceCommand("terminal-clear")
        default:
            return .invalid("Usage: /terminal or /terminal clear")
        }
    }

    private static func parseProject(_ argument: String) -> SlashCommand {
        let parts = argument.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let subcommand = parts.first?.lowercased() else {
            return .invalid("Usage: /project new, /project refresh, /project rename Name, or /project remove")
        }
        let value = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        switch subcommand {
        case "new", "new-chat", "chat":
            return .workspaceCommand("project-new-chat")
        case "refresh", "reload", "context":
            return .workspaceCommand("project-refresh-context")
        case "rename", "title":
            return value.isEmpty ? .invalid("Usage: /project rename Project name") : .renameProject(value)
        case "remove", "forget", "delete":
            return .workspaceCommand("project-remove")
        default:
            return .invalid("Unknown project command '\(subcommand)'. Use new, refresh, rename, or remove.")
        }
    }

    private static func parsePullRequest(_ argument: String) -> SlashCommand {
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
            return parsePullRequestReview(rest)
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
            return parsePullRequestReviewers(rest)
        case "labels", "label":
            return parsePullRequestLabels(rest)
        case "merge", "automerge", "auto_merge":
            return parsePullRequestMerge(rest, autoByDefault: subcommand != "merge")
        default:
            return .invalid("Unknown pull request command '\(rawSubcommand)'. Use create, view, checks, diff, checkout, comment, review, reviewers, labels, or merge.")
        }
    }

    private static func parsePullRequestReview(_ argument: String) -> SlashCommand {
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

    private static func parsePullRequestReviewers(_ argument: String) -> SlashCommand {
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

    private static func parsePullRequestLabels(_ argument: String) -> SlashCommand {
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

    private static func parsePullRequestMerge(_ argument: String, autoByDefault: Bool) -> SlashCommand {
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

    private static func parseMode(_ argument: String) -> SlashCommand {
        switch argument.lowercased() {
        case "auto":
            return .mode(.auto)
        case "review":
            return .mode(.review)
        case "read-only", "readonly", "read_only":
            return .mode(.readOnly)
        case "":
            return .invalid("Usage: /mode auto, /mode review, or /mode read-only")
        default:
            return .invalid("Unknown mode '\(argument)'. Use auto, review, or read-only.")
        }
    }
}
