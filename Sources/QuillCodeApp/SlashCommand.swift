import Foundation
import QuillCodeCore

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
        .init(usage: "/follow-up when", title: "Schedule follow-up", detail: "Create a scheduled follow-up for this thread, for example in 30 minutes or tomorrow at 9 AM.", insertText: "/follow-up in ", aliases: ["followup", "schedule follow-up", "remind", "automation"]),
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
        .init(usage: "/pr", title: "Prepare pull request", detail: "Draft a pull request request in the composer.", insertText: "/pr", aliases: ["pull-request", "pullrequest"]),
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
    case workspaceCommand(String)
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
                ? .invalid("Usage: /follow-up in 30 minutes or /follow-up tomorrow at 9 AM")
                : .threadFollowUp(argument)
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
            return .workspaceCommand("git-pr-create")
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
