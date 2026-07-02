import Foundation

enum WorkspaceCommandPaletteRanker {
    static func rankedCommands(
        _ commands: [WorkspaceCommandSurface],
        matching query: String
    ) -> [WorkspaceCommandSurface] {
        let request = QueryRequest(query)
        let searchableCommands = request.searchableCommands(from: commands)
        let scoredCommands = searchableCommands.enumerated().compactMap { index, command in
            score(command, query: request.normalizedQuery).map { score in
                (index: index, command: command, score: score)
            }
        }
        return scoredCommands.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            let lhsCategory = categoryRank(lhs.command.category)
            let rhsCategory = categoryRank(rhs.command.category)
            if lhsCategory != rhsCategory {
                return lhsCategory < rhsCategory
            }
            return lhs.index < rhs.index
        }
        .map(\.command)
    }

    static func groupedCommands(
        _ commands: [WorkspaceCommandSurface],
        matching query: String
    ) -> [WorkspaceCommandGroupSurface] {
        var groupsByCategory: [String: [WorkspaceCommandSurface]] = [:]
        for command in rankedCommands(commands, matching: query) {
            groupsByCategory[command.category, default: []].append(command)
        }
        return groupsByCategory.keys.sorted { lhs, rhs in
            let lhsRank = categoryRank(lhs)
            let rhsRank = categoryRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs < rhs
        }
        .map { category in
            WorkspaceCommandGroupSurface(title: category, commands: groupsByCategory[category] ?? [])
        }
    }

    private static func score(_ command: WorkspaceCommandSurface, query: String) -> Int? {
        guard !query.isEmpty else {
            return 1
        }

        let title = normalize(command.title)
        let compactTitle = compact(title)
        let shortcut = shortcutSearchText(command.shortcut)
        let id = normalize(command.id.replacingOccurrences(of: "-", with: " "))
        let category = normalize(command.category)
        let keywords = command.keywords.map(normalize)
        let compactQuery = compact(query)

        if title == query || compactTitle == compactQuery {
            return 1_000
        }
        if title.hasPrefix(query) || compactTitle.hasPrefix(compactQuery) {
            return 900
        }
        if title.split(separator: " ").contains(where: { $0.hasPrefix(query) }) {
            return 820
        }
        if !shortcut.isEmpty && shortcut.contains(compactQuery) {
            return 780
        }
        if keywords.contains(where: { $0 == query || $0.hasPrefix(query) }) {
            return 720
        }
        if title.contains(query) || compactTitle.contains(compactQuery) {
            return 650
        }
        if id.contains(query) || keywords.contains(where: { $0.contains(query) }) {
            return 560
        }
        let tokens = queryTokens(query)
        if tokens.count > 1 {
            let searchableTokens = commandTokens(title: title, id: id, category: category, keywords: keywords)
            if tokens.allSatisfy({ token in searchableTokens.contains(where: { $0.hasPrefix(token) }) }) {
                return 520
            }
        }
        if category.contains(query) {
            return 440
        }
        return nil
    }

    private static func queryTokens(_ query: String) -> [Substring] {
        query.split(whereSeparator: \.isWhitespace)
    }

    private static func commandTokens(
        title: String,
        id: String,
        category: String,
        keywords: [String]
    ) -> [Substring] {
        ([title, id, category] + keywords)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
    }

    private static func shortcutSearchText(_ shortcut: String?) -> String {
        compact(
            normalize(shortcut ?? "")
                .replacingOccurrences(of: "←", with: " left arrowleft")
                .replacingOccurrences(of: "→", with: " right arrowright")
        )
    }

    private struct QueryRequest {
        enum Scope {
            case mixed
            case actions
            case slash
        }

        var scope: Scope
        var normalizedQuery: String

        init(_ rawQuery: String) {
            let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix(">") {
                self.scope = .actions
                self.normalizedQuery = WorkspaceCommandPaletteRanker.normalize(String(trimmed.dropFirst()))
            } else if trimmed.hasPrefix("/") {
                self.scope = .slash
                self.normalizedQuery = WorkspaceCommandPaletteRanker.normalize(String(trimmed.dropFirst()))
            } else {
                self.scope = .mixed
                self.normalizedQuery = WorkspaceCommandPaletteRanker.normalize(trimmed)
            }
        }

        func searchableCommands(from commands: [WorkspaceCommandSurface]) -> [WorkspaceCommandSurface] {
            switch scope {
            case .actions:
                return commands
            case .slash:
                return SlashCommandCatalog.commandPaletteCommands()
            case .mixed:
                guard !normalizedQuery.isEmpty else { return commands }
                return commands + SlashCommandCatalog.commandPaletteCommands()
            }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func compact(_ value: String) -> String {
        value.filter { !$0.isWhitespace && $0 != "+" }
    }

    private static func categoryRank(_ category: String) -> Int {
        WorkspaceCommandPalette.categoryOrder.firstIndex(of: category) ?? WorkspaceCommandPalette.categoryOrder.count
    }
}
