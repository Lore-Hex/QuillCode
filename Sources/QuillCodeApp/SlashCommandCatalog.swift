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

    static let definitions: [SlashCommandDefinition] =
        prefixDefinitions
        + WorkspacePullRequestCommandCatalog.slashDefinitions
        + suffixDefinitions

    private static let prefixDefinitions: [SlashCommandDefinition] = [
        .init(usage: "/help", title: "Show slash commands", detail: "List the available composer commands.", insertText: "/help", aliases: ["?"]),
        .init(usage: "/status", title: "Show status", detail: "Summarize the active project, mode, model, and loaded context.", insertText: "/status", aliases: []),
        .init(usage: "/new", title: "New chat", detail: "Start a fresh thread in the selected project.", insertText: "/new", aliases: ["new-chat", "newchat"]),
        .init(usage: "/rename title", title: "Rename chat", detail: "Rename the current thread.", insertText: "/rename ", aliases: ["rename-chat", "title"]),
        .init(usage: "/duplicate", title: "Duplicate chat", detail: "Copy the current thread into a new one.", insertText: "/duplicate", aliases: ["duplicate-chat", "copy-chat"]),
        .init(usage: "/archive", title: "Archive chat", detail: "Move the current thread out of the recent list.", insertText: "/archive", aliases: ["archive-chat"]),
        .init(usage: "/unarchive", title: "Unarchive chat", detail: "Restore the current archived thread.", insertText: "/unarchive", aliases: ["unarchive-chat"]),
        .init(usage: "/compact", title: "Compact context", detail: "Create a shorter continuation thread from the latest turns.", insertText: "/compact", aliases: ["compact-context", "context-compact"]),
        .init(usage: "/follow-up when", title: "Schedule follow-up", detail: "Create a scheduled follow-up for this thread, for example in 30 minutes, Friday at 4 PM, tonight, or daily.", insertText: "/follow-up in ", aliases: ["followup", "schedule follow-up", "remind", "automation"]),
        .init(usage: "/workspace-check when", title: "Schedule workspace check", detail: "Create a scheduled check for the selected project, for example in 1 hour, Friday morning, next Monday at noon, or every 2 hours.", insertText: "/workspace-check in ", aliases: ["workspace schedule", "schedule workspace", "project check", "repo check", "automation workspace"]),
        .init(usage: "/subagents objective | Name: role", title: "Run subagents", detail: "Fan out a local parallel subagent workflow and show replayable progress in Activity.", insertText: "/subagents ", aliases: ["subagent", "parallel agents", "agents"]),
        .init(usage: "/project new", title: "Project new chat", detail: "Start a new thread in the selected project.", insertText: "/project new", aliases: ["project chat"]),
        .init(usage: "/project refresh", title: "Refresh project context", detail: "Reload instructions, local actions, extensions, and memories.", insertText: "/project refresh", aliases: ["project reload", "project context"]),
        .init(usage: "/init", title: "Initialize AGENTS.md", detail: "Scaffold a starter AGENTS.md for the project from its build and test commands.", insertText: "/init", aliases: ["init-project", "scaffold", "agents"]),
        .init(usage: "/project rename name", title: "Rename project", detail: "Rename the selected project in QuillCode.", insertText: "/project rename ", aliases: ["project title"]),
        .init(usage: "/project remove", title: "Remove project", detail: "Forget the selected project from the sidebar without deleting files.", insertText: "/project remove", aliases: ["project forget"]),
        .init(usage: "/ssh user@host:/path", title: "Add SSH Remote", detail: "Register an SSH Remote workspace in the project sidebar.", insertText: "/ssh ", aliases: ["remote", "ssh project"]),
        .init(usage: "/terminal", title: "Toggle terminal", detail: "Show or hide the integrated workspace terminal.", insertText: "/terminal", aliases: ["term", "shell"]),
        .init(usage: "/terminal clear", title: "Clear terminal history", detail: "Clear completed integrated-terminal history without resetting cwd or environment.", insertText: "/terminal clear", aliases: ["term clear", "shell clear"]),
        .init(usage: "/browser", title: "Toggle browser", detail: "Show or hide the browser preview panel.", insertText: "/browser", aliases: ["preview"]),
        .init(usage: "/diff", title: "Review diff", detail: "Show the working-tree git diff in the review pane.", insertText: "/diff", aliases: ["changes", "git diff"]),
        .init(usage: "/git-status", title: "Git status", detail: "Show the git status of the selected project.", insertText: "/git-status", aliases: ["gitstatus", "git status"]),
        .init(usage: "/memories", title: "Show memories", detail: "Show loaded global and project memories.", insertText: "/memories", aliases: ["memory"]),
        .init(usage: "/remember text", title: "Add memory", detail: "Save an explicit global memory after redaction checks.", insertText: "/remember ", aliases: []),
        .init(usage: "/worktrees", title: "List worktrees", detail: "List git worktrees for the selected project.", insertText: "/worktrees", aliases: ["worktree", "wt"]),
        .init(usage: "/worktree create path", title: "Create worktree", detail: "Create and open a sibling git worktree. Add --branch name or --base ref when needed.", insertText: "/worktree create ", aliases: ["worktree add", "wt create"]),
        .init(usage: "/worktree open path", title: "Open worktree", detail: "Open an existing registered git worktree as a focused project.", insertText: "/worktree open ", aliases: ["worktree switch", "wt open"]),
        .init(usage: "/worktree remove path", title: "Remove worktree", detail: "Remove an existing registered git worktree. Add --force only when needed.", insertText: "/worktree remove ", aliases: ["worktree rm", "wt remove"]),
        .init(usage: "/worktree prune", title: "Prune stale worktrees", detail: "Clean stale git worktree administrative records. Add --dry-run to preview.", insertText: "/worktree prune --dry-run", aliases: ["worktree cleanup", "wt prune"]),
    ]

    private static let suffixDefinitions: [SlashCommandDefinition] = [
        .init(usage: "/env name", title: "Run local environment action", detail: "List or run project-local environment scripts.", insertText: "/env ", aliases: ["environment", "local-env"]),
        .init(usage: "/mode auto|plan|review|read-only", title: "Set approval mode", detail: "Switch between Auto, Plan, Review, and Read-only behavior.", insertText: "/mode ", aliases: []),
        .init(usage: "/plan", title: "Enter Plan mode", detail: "Investigate read-only and propose a plan; mutating tools wait for your approval.", insertText: "/plan", aliases: []),
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
