import Foundation

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
        .init(usage: "/worktree create path", title: "Create worktree", detail: "Create and open a sibling git worktree. Add --branch name or --base ref when needed.", insertText: "/worktree create ", aliases: ["worktree add", "wt create"]),
        .init(usage: "/worktree open path", title: "Open worktree", detail: "Open an existing registered git worktree as a focused project.", insertText: "/worktree open ", aliases: ["worktree switch", "wt open"]),
        .init(usage: "/worktree remove path", title: "Remove worktree", detail: "Remove an existing registered git worktree. Add --force only when needed.", insertText: "/worktree remove ", aliases: ["worktree rm", "wt remove"]),
        .init(usage: "/worktree prune", title: "Prune stale worktrees", detail: "Clean stale git worktree administrative records. Add --dry-run to preview.", insertText: "/worktree prune --dry-run", aliases: ["worktree cleanup", "wt prune"]),
        .init(usage: "/pr create", title: "Create pull request", detail: "Draft a pull request request in the composer.", insertText: "/pr create", aliases: ["pull-request", "pullrequest"]),
        .init(usage: "/pr view [selector]", title: "View pull request", detail: "View the current or selected pull request with comments.", insertText: "/pr view ", aliases: ["pr show", "pull request view"]),
        .init(usage: "/pr checks [selector]", title: "Pull request checks", detail: "Show CI status for the current or selected pull request.", insertText: "/pr checks ", aliases: ["pr ci", "pull request status"]),
        .init(usage: "/pr diff [selector]", title: "Pull request diff", detail: "Show the unified diff for the current or selected pull request.", insertText: "/pr diff ", aliases: ["pr changes", "pull request diff"]),
        .init(usage: "/pr checkout selector", title: "Checkout pull request", detail: "Check out a pull request branch.", insertText: "/pr checkout ", aliases: ["pr switch"]),
        .init(usage: "/pr comment body", title: "Comment on pull request", detail: "Post a top-level comment on the current pull request.", insertText: "/pr comment ", aliases: ["pr reply"]),
        .init(usage: "/pr review approve|comment|request_changes", title: "Review pull request", detail: "Submit an approve, comment, or request_changes review.", insertText: "/pr review approve", aliases: ["pr approve", "request changes"]),
        .init(usage: "/pr review-comment path line body", title: "Inline pull request comment", detail: "Post an inline review comment on a pull request diff line.", insertText: "/pr review-comment ", aliases: ["pr inline", "line comment", "review comment"]),
        .init(usage: "/pr review-reply commentId body", title: "Reply to inline review comment", detail: "Reply to an existing pull request line comment.", insertText: "/pr review-reply ", aliases: ["inline reply", "review reply"]),
        .init(usage: "/pr review-thread resolve|unresolve threadId", title: "Resolve review thread", detail: "Resolve or unresolve a pull request review thread.", insertText: "/pr review-thread resolve ", aliases: ["resolve thread", "unresolve thread"]),
        .init(usage: "/pr reviewers add|remove login", title: "Manage pull request reviewers", detail: "Request or remove pull request reviewers.", insertText: "/pr reviewers add ", aliases: ["request reviewer", "remove reviewer"]),
        .init(usage: "/pr labels add|remove label", title: "Manage pull request labels", detail: "Add or remove pull request labels. Use commas for labels with spaces.", insertText: "/pr labels add ", aliases: ["pr label", "triage label"]),
        .init(usage: "/pr merge [squash|merge|rebase]", title: "Merge pull request", detail: "Merge or enable auto-merge for the current pull request.", insertText: "/pr merge squash", aliases: ["automerge", "merge train"]),
        .init(usage: "/env name", title: "Run local environment action", detail: "List or run project-local environment scripts.", insertText: "/env ", aliases: ["environment", "local-env"]),
        .init(usage: "/mode auto|review|read-only", title: "Set approval mode", detail: "Switch between Auto, Review, and Read-only behavior.", insertText: "/mode ", aliases: []),
        .init(
            usage: "/model /synth",
            title: "Set model",
            detail: "Switch the active TrustedRouter model, for example /synth or provider/model.",
            insertText: "/model ",
            aliases: []
        )
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
