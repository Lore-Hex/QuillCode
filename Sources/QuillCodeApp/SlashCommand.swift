import Foundation
import QuillCodeCore
import QuillCodeTools

public struct SlashCommandSuggestionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String { usage }
    public var usage: String
    public var title: String
    public var detail: String
    public var insertText: String

    public init(usage: String, title: String, detail: String, insertText: String) {
        self.usage = usage
        self.title = title
        self.detail = detail
        self.insertText = insertText
    }
}

struct SlashCommandDefinition: Sendable, Hashable {
    var usage: String
    var title: String
    var detail: String
    var insertText: String
    var aliases: [String]

    var searchableText: [String] {
        [usage, title, detail] + aliases
    }
}

enum SlashCommandCatalog {
    static let commandPaletteIDPrefix = "slash-command:"

    static let definitions: [SlashCommandDefinition] = [
        .init(usage: "/help", title: "Show slash commands", detail: "List the available composer commands.", insertText: "/help", aliases: ["?"]),
        .init(usage: "/status", title: "Show status", detail: "Summarize the active project, mode, model, and loaded context.", insertText: "/status", aliases: []),
        .init(usage: "/new", title: "New chat", detail: "Start a fresh thread in the selected project.", insertText: "/new", aliases: ["new-chat", "newchat"]),
        .init(usage: "/rename title", title: "Rename chat", detail: "Rename the current thread.", insertText: "/rename ", aliases: ["rename-chat", "title"]),
        .init(usage: "/duplicate", title: "Duplicate chat", detail: "Copy the current thread into a new one.", insertText: "/duplicate", aliases: ["duplicate-chat", "copy-chat"]),
        .init(usage: "/archive", title: "Archive chat", detail: "Move the current thread out of the recent list.", insertText: "/archive", aliases: ["archive-chat"]),
        .init(usage: "/unarchive", title: "Unarchive chat", detail: "Restore the current archived thread.", insertText: "/unarchive", aliases: ["unarchive-chat"]),
        .init(usage: "/compact", title: "Compact context", detail: "Create a shorter continuation thread from the latest turns.", insertText: "/compact", aliases: ["compact-context", "context-compact"]),
        .init(usage: "/follow-up when", title: "Schedule follow-up", detail: "Create a scheduled follow-up for this thread, for example in 30 minutes, tomorrow at 9 AM, or daily.", insertText: "/follow-up in ", aliases: ["followup", "schedule follow-up", "remind", "automation"]),
        .init(usage: "/workspace-check when", title: "Schedule workspace check", detail: "Create a scheduled check for the selected project, for example in 1 hour, tomorrow morning, or every 2 hours.", insertText: "/workspace-check in ", aliases: ["workspace schedule", "schedule workspace", "project check", "repo check", "automation workspace"]),
        .init(usage: "/project new", title: "Project new chat", detail: "Start a new thread in the selected project.", insertText: "/project new", aliases: ["project chat"]),
        .init(usage: "/project refresh", title: "Refresh project context", detail: "Reload instructions, local actions, extensions, and memories.", insertText: "/project refresh", aliases: ["project reload", "project context"]),
        .init(usage: "/project rename name", title: "Rename project", detail: "Rename the selected project in QuillCode.", insertText: "/project rename ", aliases: ["project title"]),
        .init(usage: "/project remove", title: "Remove project", detail: "Forget the selected project from the sidebar without deleting files.", insertText: "/project remove", aliases: ["project forget"]),
        .init(usage: "/ssh user@host:/path", title: "Add SSH Remote", detail: "Register an SSH Remote workspace in the project sidebar.", insertText: "/ssh ", aliases: ["remote", "ssh project"]),
        .init(usage: "/terminal", title: "Toggle terminal", detail: "Show or hide the integrated workspace terminal.", insertText: "/terminal", aliases: ["term", "shell"]),
        .init(usage: "/terminal clear", title: "Clear terminal history", detail: "Clear completed integrated-terminal history without resetting cwd or environment.", insertText: "/terminal clear", aliases: ["term clear", "shell clear"]),
        .init(usage: "/browser", title: "Toggle browser", detail: "Show or hide the browser preview panel.", insertText: "/browser", aliases: ["preview"]),
        .init(usage: "/memories", title: "Show memories", detail: "Show loaded global and project memories.", insertText: "/memories", aliases: ["memory"]),
        .init(usage: "/remember text", title: "Add memory", detail: "Save an explicit global memory after redaction checks.", insertText: "/remember ", aliases: []),
        .init(usage: "/worktrees", title: "List worktrees", detail: "List git worktrees for the selected project.", insertText: "/worktrees", aliases: ["worktree", "wt"]),
        .init(usage: "/pr create", title: "Create pull request", detail: "Draft a pull request request in the composer.", insertText: "/pr create", aliases: ["pull-request", "pullrequest"]),
        .init(usage: "/pr view [selector]", title: "View pull request", detail: "View the current or selected pull request with comments.", insertText: "/pr view ", aliases: ["pr show", "pull request view"]),
        .init(usage: "/pr checks [selector]", title: "Pull request checks", detail: "Show CI status for the current or selected pull request.", insertText: "/pr checks ", aliases: ["pr ci", "pull request status"]),
        .init(usage: "/pr checkout selector", title: "Checkout pull request", detail: "Check out a pull request branch.", insertText: "/pr checkout ", aliases: ["pr switch"]),
        .init(usage: "/pr comment body", title: "Comment on pull request", detail: "Post a top-level comment on the current pull request.", insertText: "/pr comment ", aliases: ["pr reply"]),
        .init(usage: "/pr review approve|comment|request_changes", title: "Review pull request", detail: "Submit an approve, comment, or request_changes review.", insertText: "/pr review approve", aliases: ["pr approve", "request changes"]),
        .init(usage: "/pr reviewers add|remove login", title: "Manage pull request reviewers", detail: "Request or remove pull request reviewers.", insertText: "/pr reviewers add ", aliases: ["request reviewer", "remove reviewer"]),
        .init(usage: "/pr merge [squash|merge|rebase]", title: "Merge pull request", detail: "Merge or enable auto-merge for the current pull request.", insertText: "/pr merge squash", aliases: ["automerge", "merge train"]),
        .init(usage: "/env name", title: "Run local environment action", detail: "List or run project-local environment scripts.", insertText: "/env ", aliases: ["environment", "local-env"]),
        .init(usage: "/mode auto|review|read-only", title: "Set approval mode", detail: "Switch between Auto, Review, and Read-only behavior.", insertText: "/mode ", aliases: []),
        .init(usage: "/model provider/model", title: "Set model", detail: "Switch the active TrustedRouter model.", insertText: "/model ", aliases: [])
    ]

    static func helpText() -> String {
        let commandLines = definitions.map { "\($0.usage) - \($0.detail)" }
        return (["Slash commands:"] + commandLines).joined(separator: "\n")
    }

    static func commandPaletteCommands() -> [WorkspaceCommandSurface] {
        definitions.enumerated().map { index, definition in
            WorkspaceCommandSurface(
                id: "\(commandPaletteIDPrefix)\(index)",
                title: definition.usage,
                category: WorkspaceCommandPalette.slashCategory,
                keywords: [String(definition.usage.dropFirst()), definition.title, definition.detail] + definition.aliases
            )
        }
    }

    static func insertText(forCommandPaletteID id: String) -> String? {
        guard id.hasPrefix(commandPaletteIDPrefix) else { return nil }
        let rawIndex = String(id.dropFirst(commandPaletteIDPrefix.count))
        guard let index = Int(rawIndex),
              definitions.indices.contains(index)
        else {
            return nil
        }
        return definitions[index].insertText
    }

    static func suggestions(for draft: String, limit: Int = 6) -> [SlashCommandSuggestionSurface] {
        let trimmedLeading = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLeading.hasPrefix("/"), !trimmedLeading.contains("\n") else { return [] }
        let query = normalize(String(trimmedLeading.dropFirst()))
        let scored = definitions.enumerated().compactMap { index, definition -> (Int, SlashCommandDefinition, Int)? in
            score(definition, query: query).map { (index, definition, $0) }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.2 != rhs.2 {
                    return lhs.2 > rhs.2
                }
                return lhs.0 < rhs.0
            }
            .prefix(limit)
            .map { _, definition, _ in
                SlashCommandSuggestionSurface(
                    usage: definition.usage,
                    title: definition.title,
                    detail: definition.detail,
                    insertText: definition.insertText
                )
            }
    }

    private static func score(_ definition: SlashCommandDefinition, query: String) -> Int? {
        guard !query.isEmpty else { return 100 }
        let usage = normalize(String(definition.usage.dropFirst()))
        if usage.hasPrefix(query) {
            return 120
        }
        if definition.aliases.map(normalize).contains(where: { $0.hasPrefix(query) }) {
            return 110
        }
        if usage.contains(query) {
            return 90
        }
        if definition.searchableText.map(normalize).contains(where: { $0.contains(query) }) {
            return 70
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
                return .invalid("Usage: /model provider/model")
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
        case "request_changes", "changes":
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
        case "merge", "automerge", "auto_merge":
            return parsePullRequestMerge(rest, autoByDefault: subcommand != "merge")
        default:
            return .invalid("Unknown pull request command '\(rawSubcommand)'. Use create, view, checks, checkout, comment, review, reviewers, or merge.")
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
        .toolCall(ToolCall(name: definition.name, argumentsJSON: json(arguments)))
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

    private static func json(_ values: [String: Any]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
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
