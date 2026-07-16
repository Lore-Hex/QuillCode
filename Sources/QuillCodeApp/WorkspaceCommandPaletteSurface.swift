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
            "toggle-sidebar",
            "search"
        ]
        if showsComputerUseSetup {
            commandIDs.append("computer-use-setup")
        }
        commandIDs.append(contentsOf: [
            WorkspaceCommandAction.threadPublishBranch.rawValue,
            WorkspaceCommandAction.threadRefreshPullRequest.rawValue,
            WorkspaceCommandAction.threadLandPullRequest.rawValue,
            WorkspaceCommandAction.threadCleanupMergedWorktree.rawValue,
            WorkspaceCommandAction.threadFinishWorktree.rawValue,
            "settings",
            "keyboard-shortcuts",
            "disconnect-all"
        ])
        return commandIDs
    }

    public static func commands(
        from commands: [WorkspaceCommandSurface],
        showsComputerUseSetup: Bool
    ) -> [WorkspaceCommandSurface] {
        commandIDs(showsComputerUseSetup: showsComputerUseSetup).compactMap { commandID in
            commands.first { $0.id == commandID }
        }.filter { command in
            switch command.id {
            case "disconnect-all",
                 WorkspaceCommandAction.threadPublishBranch.rawValue,
                 WorkspaceCommandAction.threadRefreshPullRequest.rawValue,
                 WorkspaceCommandAction.threadLandPullRequest.rawValue,
                 WorkspaceCommandAction.threadCleanupMergedWorktree.rawValue,
                 WorkspaceCommandAction.threadFinishWorktree.rawValue:
                command.isEnabled
            default:
                true
            }
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

public enum TopBarProjectActionCatalog {
    public static let commandIDPrefix = "local-env:"
    public static let testID = "top-bar-project-action"

    public static func commands(
        from commands: [WorkspaceCommandSurface]
    ) -> [WorkspaceCommandSurface] {
        commands.filter { command in
            command.isEnabled
                && command.category == WorkspaceCommandPalette.environmentCategory
                && command.id.hasPrefix(commandIDPrefix)
        }
    }
}

public extension WorkspaceCommandSurface {
    static func workflowRecordSkill(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "workflow-recording-create",
            title: "Record a skill",
            category: WorkspaceCommandPalette.extensionsCategory,
            keywords: ["record", "replay", "workflow", "computer use", "skill"],
            isEnabled: isEnabled
        )
    }

    static func workflowStopRecording(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: WorkspaceCommandAction.workflowRecordingStop.rawValue,
            title: "Stop recording",
            category: WorkspaceCommandPalette.extensionsCategory,
            keywords: ["stop", "finish", "record", "skill"],
            isEnabled: isEnabled
        )
    }

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

    static func automationCreateMonitor(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "automation-create-monitor",
            title: "Create monitor",
            category: WorkspaceCommandPalette.automationsCategory,
            keywords: [
                "automation",
                "monitor",
                "watch",
                "event",
                "file",
                "directory",
                "folder",
                "url",
                "last-modified",
                "feed",
                "rss",
                "atom"
            ],
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

    static func trustedRouterCreditsRefresh(isEnabled: Bool) -> WorkspaceCommandSurface {
        WorkspaceCommandSurface(
            id: "trustedrouter-credits-refresh",
            title: "Refresh TrustedRouter balance",
            category: WorkspaceCommandPalette.workspaceCategory,
            keywords: ["trustedrouter", "account", "balance", "credits", "refresh"],
            isEnabled: isEnabled
        )
    }
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
        WorkspaceCommandPaletteRanker.rankedCommands(commands, matching: query)
    }

    public static func groupedCommands(
        _ commands: [WorkspaceCommandSurface],
        matching query: String
    ) -> [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPaletteRanker.groupedCommands(commands, matching: query)
    }

    public static func groupedActionCommands(
        _ commands: [WorkspaceCommandSurface],
        matching query: String
    ) -> [WorkspaceCommandGroupSurface] {
        WorkspaceCommandPaletteRanker.groupedActionCommands(commands, matching: query)
    }
}
