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
        globalPrefixDefinitions
        + WorkspacePullRequestCommandCatalog.slashDefinitions
        + globalSuffixDefinitions

    static func helpText() -> String {
        let groupedDefinitions = helpCategoryOrder.compactMap { category in
            let rows = definitions
                .filter { helpCategory(for: $0) == category }
                .map { "- `\($0.usage)` - \($0.detail)" }
            return rows.isEmpty ? nil : ([category + ":"] + rows).joined(separator: "\n")
        }
        return (["Slash commands:"] + groupedDefinitions).joined(separator: "\n\n")
    }

    static func commandPaletteCommands() -> [WorkspaceCommandSurface] {
        definitions.enumerated().map { index, definition in
            let keywords = [
                String(definition.usage.dropFirst()),
                definition.title,
                definition.detail
            ] + definition.aliases

            return WorkspaceCommandSurface(
                id: "\(commandPaletteIDPrefix)\(index)",
                title: definition.usage,
                category: WorkspaceCommandPalette.slashCategory,
                keywords: keywords
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

    static func suggestions(
        for draft: String,
        limit: Int = 6,
        supportsPersonality: Bool = true
    ) -> [SlashCommandSuggestionSurface] {
        let trimmedLeading = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLeading.hasPrefix("/"), !trimmedLeading.contains("\n") else { return [] }
        let query = normalize(String(trimmedLeading.dropFirst()))
        let scored = definitions.enumerated().compactMap { index, definition -> (Int, SlashCommandDefinition, Int)? in
            if !supportsPersonality, definition.usage.hasPrefix("/personality ") {
                return nil
            }
            return score(definition, query: query).map { (index, definition, $0) }
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
        if usage.split(whereSeparator: \.isWhitespace).first.map(String.init) == query {
            return 130
        }
        if usage.hasPrefix(query) {
            return 120
        }
        if definition.aliases.map(normalize).contains(where: { $0.hasPrefix(query) }) {
            return 110
        }
        if usage.contains(query) {
            return 90
        }
        // The low-weight free-text fallback (matching title/detail/aliases as a substring) is a
        // KEYWORD search — it must only apply while the user is still typing the command word. Once
        // the query contains whitespace the user has moved on to typing an ARGUMENT (`/skill foo`),
        // and a stray substring hit inside the detail's own usage-example (".../skill code-review")
        // must NOT keep the command as a live suggestion — that left the popup open and let Enter
        // re-accept the bare `/skill ` insertText, dropping the typed argument and blocking submit.
        guard !query.contains(" ") else { return nil }
        if definition.searchableText.map(normalize).contains(where: { $0.contains(query) }) {
            return 70
        }
        return nil
    }

    private static let helpCategoryOrder = [
        "Runtime and models",
        "Chats",
        "Workspace",
        "Git and review",
        "Browser",
        "Memory",
        "Automations and agents",
        "Extensions",
        "Local environment"
    ]

    private static func helpCategory(for definition: SlashCommandDefinition) -> String {
        let usage = definition.usage
        if usage.hasPrefix("/pr ")
            || usage.hasPrefix("/review")
            || usage.hasPrefix("/diff")
            || usage.hasPrefix("/git")
            || usage.hasPrefix("/branch")
            || usage.hasPrefix("/worktree") {
            return "Git and review"
        }
        if usage.hasPrefix("/browser") || usage.hasPrefix("/session") {
            return "Browser"
        }
        if usage.hasPrefix("/memories")
            || usage.hasPrefix("/remember")
            || usage.hasPrefix("/forget") {
            return "Memory"
        }
        if usage.hasPrefix("/follow-up")
            || usage.hasPrefix("/workspace-check")
            || usage.hasPrefix("/monitor")
            || usage.hasPrefix("/subagents")
            || usage.hasPrefix("/automations") {
            return "Automations and agents"
        }
        if usage.hasPrefix("/extensions")
            || usage.hasPrefix("/skills")
            || usage.hasPrefix("/skill ") {
            return "Extensions"
        }
        if usage.hasPrefix("/env") {
            return "Local environment"
        }
        if usage.hasPrefix("/project")
            || usage.hasPrefix("/init")
            || usage.hasPrefix("/ssh")
            || usage.hasPrefix("/terminal")
            || usage.hasPrefix("/search")
            || usage.hasPrefix("/find")
            || usage.hasPrefix("/focus")
            || usage.hasPrefix("/sidebar")
            || usage.hasPrefix("/copy")
            || usage.hasPrefix("/export")
            || usage.hasPrefix("/settings")
            || usage.hasPrefix("/computer-use")
            || usage.hasPrefix("/shortcuts")
            || usage.hasPrefix("/commands")
            || usage.hasPrefix("/activity")
            || usage.hasPrefix("/disconnect") {
            return "Workspace"
        }
        if usage.hasPrefix("/new")
            || usage.hasPrefix("/clear")
            || usage.hasPrefix("/undo")
            || usage.hasPrefix("/rename")
            || usage.hasPrefix("/duplicate")
            || usage.hasPrefix("/pin")
            || usage.hasPrefix("/unpin")
            || usage.hasPrefix("/archive")
            || usage.hasPrefix("/unarchive")
            || usage.hasPrefix("/delete")
            || usage.hasPrefix("/fork")
            || usage.hasPrefix("/compact")
            || usage.hasPrefix("/stop")
            || usage.hasPrefix("/retry")
            || usage.hasPrefix("/back")
            || usage.hasPrefix("/forward")
            || usage.hasPrefix("/history") {
            return "Chats"
        }
        return "Runtime and models"
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
