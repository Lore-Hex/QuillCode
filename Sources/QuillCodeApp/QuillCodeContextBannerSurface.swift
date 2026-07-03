import Foundation

public struct ContextBannerSurface: Codable, Sendable, Hashable {
    public var usedPercent: Int
    public var title: String
    public var subtitle: String
    public var progress: ContextBannerProgressSurface?
    public var newThreadCommand: WorkspaceCommandSurface
    public var forkCommand: WorkspaceCommandSurface
    public var forkCommands: [WorkspaceCommandSurface]
    public var compactCommand: WorkspaceCommandSurface

    public init(
        usedPercent: Int,
        title: String,
        subtitle: String,
        progress: ContextBannerProgressSurface? = nil,
        newThreadCommand: WorkspaceCommandSurface,
        forkCommand: WorkspaceCommandSurface,
        forkCommands: [WorkspaceCommandSurface]? = nil,
        compactCommand: WorkspaceCommandSurface = WorkspaceCommandSurface(
            id: "compact-context",
            title: "Compact context"
        )
    ) {
        self.usedPercent = usedPercent
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.newThreadCommand = newThreadCommand
        self.forkCommand = forkCommand
        self.forkCommands = Self.normalizedForkCommands(primary: forkCommand, commands: forkCommands)
        self.compactCommand = compactCommand
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent, title, subtitle, progress, newThreadCommand
        case forkCommand, forkCommands, compactCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedForkCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .forkCommand)
        self.usedPercent = try container.decode(Int.self, forKey: .usedPercent)
        self.title = try container.decode(String.self, forKey: .title)
        self.subtitle = try container.decode(String.self, forKey: .subtitle)
        self.progress = try container.decodeIfPresent(ContextBannerProgressSurface.self, forKey: .progress)
        self.newThreadCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .newThreadCommand)
        self.forkCommand = decodedForkCommand
        self.forkCommands = Self.normalizedForkCommands(
            primary: decodedForkCommand,
            commands: try container.decodeIfPresent([WorkspaceCommandSurface].self, forKey: .forkCommands)
        )
        self.compactCommand = try container.decodeIfPresent(
            WorkspaceCommandSurface.self,
            forKey: .compactCommand
        ) ?? WorkspaceCommandSurface(
            id: "compact-context",
            title: "Compact context",
            category: WorkspaceCommandPalette.threadCategory,
            keywords: ["thread", "context", "summarize", "compact"],
            isEnabled: decodedForkCommand.isEnabled
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encode(newThreadCommand, forKey: .newThreadCommand)
        try container.encode(forkCommand, forKey: .forkCommand)
        try container.encode(forkCommands, forKey: .forkCommands)
        try container.encode(compactCommand, forKey: .compactCommand)
    }

    private static func normalizedForkCommands(
        primary: WorkspaceCommandSurface,
        commands: [WorkspaceCommandSurface]?
    ) -> [WorkspaceCommandSurface] {
        var seenIDs: Set<String> = []
        return ([primary] + (commands ?? []))
            .filter { command in
                guard !seenIDs.contains(command.id) else { return false }
                seenIDs.insert(command.id)
                return true
            }
    }
}

public struct ContextBannerProgressSurface: Codable, Sendable, Hashable {
    public var activeCommandID: String
    public var title: String
    public var detail: String
    public var statusLabel: String

    public init(
        activeCommandID: String,
        title: String,
        detail: String,
        statusLabel: String = "Running"
    ) {
        self.activeCommandID = activeCommandID
        self.title = title
        self.detail = detail
        self.statusLabel = statusLabel
    }
}
