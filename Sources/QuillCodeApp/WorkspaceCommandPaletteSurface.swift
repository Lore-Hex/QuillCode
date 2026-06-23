import Foundation

public struct WorkspaceCommandSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var shortcut: String?
    public var category: String
    public var keywords: [String]
    public var isEnabled: Bool

    public init(
        id: String,
        title: String,
        shortcut: String? = nil,
        category: String = WorkspaceCommandPalette.workspaceCategory,
        keywords: [String] = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.shortcut = shortcut
        self.category = category
        self.keywords = keywords
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case shortcut
        case category
        case keywords
        case isEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
        self.category = try container.decodeIfPresent(String.self, forKey: .category)
            ?? WorkspaceCommandPalette.workspaceCategory
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        try container.encode(category, forKey: .category)
        try container.encode(keywords, forKey: .keywords)
        try container.encode(isEnabled, forKey: .isEnabled)
    }
}

public enum TopBarOverflowCommandCatalog {
    public static func commandIDs(showsComputerUseSetup: Bool) -> [String] {
        var commandIDs = [
            "command-palette",
            "search"
        ]
        if showsComputerUseSetup {
            commandIDs.append("computer-use-setup")
        }
        commandIDs.append(contentsOf: [
            "settings",
            "keyboard-shortcuts",
            "stop-all"
        ])
        return commandIDs
    }

    public static func commands(
        from commands: [WorkspaceCommandSurface],
        showsComputerUseSetup: Bool
    ) -> [WorkspaceCommandSurface] {
        commandIDs(showsComputerUseSetup: showsComputerUseSetup).compactMap { commandID in
            commands.first { $0.id == commandID }
        }
    }

    public static func testID(for commandID: String) -> String {
        switch commandID {
        case "computer-use-setup":
            return "top-bar-overflow-computer-use"
        default:
            return "top-bar-overflow-\(commandID)"
        }
    }
}

public extension WorkspaceCommandSurface {
    static func automationCreateThreadFollowUp(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "automation-create-thread-follow-up",
            title: "Create thread follow-up",
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule"],
            isEnabled: isEnabled
        )
    }

    static func automationCreateWorkspaceSchedule(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "automation-create-workspace-schedule",
            title: "Create workspace schedule",
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: ["automation", "workspace", "schedule", "repo", "check", "cron"],
            isEnabled: isEnabled
        )
    }

    static func automationScheduleThreadFollowUpCommands(isEnabled: Bool) -> [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-after:600",
                title: "In 10 minutes",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "ten minutes"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-after:3600",
                title: "In 1 hour",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "hour"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-tomorrow",
                title: "Tomorrow morning",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "tomorrow", "morning"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-thread-follow-up-every:daily",
                title: "Daily follow-up",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "follow-up", "thread", "heartbeat", "schedule", "daily", "recurring"],
                isEnabled: isEnabled
            )
        ]
    }

    static func automationScheduleWorkspaceScheduleCommands(isEnabled: Bool) -> [WorkspaceCommandSurface] {
        [
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-after:600",
                title: "Check in 10 minutes",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "ten minutes"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-after:3600",
                title: "Check in 1 hour",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "hour"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-tomorrow",
                title: "Check tomorrow morning",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "tomorrow", "morning"],
                isEnabled: isEnabled
            ),
            WorkspaceCommandSurface(
                id: "automation-create-workspace-schedule-every:daily",
                title: "Check daily",
                category: WorkspaceCommandPalette.automationsCategory,
                keywords: ["automation", "workspace", "schedule", "repo", "check", "daily", "recurring", "cron"],
                isEnabled: isEnabled
            )
        ]
    }

    static func computerUseSetup(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "computer-use-setup",
            title: "Computer Use setup",
            category: WorkspaceCommandPalette.computerUseCategory,
            keywords: ["screen", "accessibility", "permissions"],
            isEnabled: isEnabled
        )
    }

    static func computerUseScreenRecordingSettings(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "computer-use-open-screen-recording",
            title: "Open Screen Recording settings",
            category: WorkspaceCommandPalette.computerUseCategory,
            keywords: ["screen", "recording", "capture", "permissions"],
            isEnabled: isEnabled
        )
    }

    static func computerUseAccessibilitySettings(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "computer-use-open-accessibility",
            title: "Open Accessibility settings",
            category: WorkspaceCommandPalette.computerUseCategory,
            keywords: ["accessibility", "click", "keyboard", "permissions"],
            isEnabled: isEnabled
        )
    }

    static let computerUseRefresh = WorkspaceCommandSurface(
        id: "computer-use-refresh",
        title: "Refresh Computer Use status",
        category: WorkspaceCommandPalette.computerUseCategory,
        keywords: ["computer use", "permissions", "refresh", "status"]
    )
}

public struct WorkspaceCommandGroupSurface: Sendable, Hashable, Identifiable {
    public var id: String { title }
    public var title: String
    public var commands: [WorkspaceCommandSurface]
}

public enum WorkspaceCommandPalette {
    public static let threadCategory = "Thread"
    public static let navigationCategory = "Navigation"
    public static let workspaceCategory = "Workspace"
    public static let slashCategory = "Slash Commands"
    public static let gitCategory = "Git"
    public static let environmentCategory = "Environment"
    public static let controlCategory = "Control"
    public static let computerUseCategory = "Computer Use"
    public static let automationsCategory = "Automations"
    public static let extensionsCategory = "Extensions"
    public static let memoriesCategory = "Memories"

    public static let categoryOrder = [
        threadCategory,
        navigationCategory,
        workspaceCategory,
        automationsCategory,
        memoriesCategory,
        extensionsCategory,
        gitCategory,
        slashCategory,
        environmentCategory,
        controlCategory,
        computerUseCategory
    ]

    public static func rankedCommands(
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

    public static func groupedCommands(
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
        let shortcut = compact(normalize(command.shortcut ?? ""))
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
                self.normalizedQuery = WorkspaceCommandPalette.normalize(String(trimmed.dropFirst()))
            } else if trimmed.hasPrefix("/") {
                self.scope = .slash
                self.normalizedQuery = WorkspaceCommandPalette.normalize(String(trimmed.dropFirst()))
            } else {
                self.scope = .mixed
                self.normalizedQuery = WorkspaceCommandPalette.normalize(trimmed)
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
        categoryOrder.firstIndex(of: category) ?? categoryOrder.count
    }
}
