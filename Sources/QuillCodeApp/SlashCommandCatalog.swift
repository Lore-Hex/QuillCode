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
        let commandLines = definitions.map { "\($0.usage) - \($0.detail)" }
        return (["Slash commands:"] + commandLines).joined(separator: "\n")
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

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
