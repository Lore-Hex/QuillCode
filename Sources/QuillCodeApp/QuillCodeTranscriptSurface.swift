import Foundation
import QuillCodeCore

public struct TranscriptSurface: Codable, Sendable, Hashable {
    public var messages: [MessageSurface]
    public var toolCards: [ToolCardState]
    public var timelineItems: [TranscriptTimelineItemSurface]
    public var thinking: TranscriptThinkingSurface?
    public var emptyTitle: String
    public var emptySubtitle: String
    public var emptyStarterActions: [TranscriptStarterActionSurface]

    public init(
        messages: [MessageSurface],
        toolCards: [ToolCardState],
        timelineItems: [TranscriptTimelineItemSurface]? = nil,
        thinking: TranscriptThinkingSurface? = nil,
        emptyTitle: String = "Ask QuillCode to inspect, edit, or run this project.",
        emptySubtitle: String = "Use Auto for normal coding work, Review for manual gates, or Read-only for exploration.",
        emptyStarterActions: [TranscriptStarterActionSurface] = TranscriptStarterActionSurface.defaults
    ) {
        self.messages = messages
        self.toolCards = toolCards
        self.timelineItems = timelineItems ?? messages.map(TranscriptTimelineItemSurface.message)
            + toolCards.map(TranscriptTimelineItemSurface.toolCard)
        self.thinking = thinking
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
        self.emptyStarterActions = emptyStarterActions
    }

    private enum CodingKeys: String, CodingKey {
        case messages
        case toolCards
        case timelineItems
        case thinking
        case emptyTitle
        case emptySubtitle
        case emptyStarterActions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.messages = try container.decode([MessageSurface].self, forKey: .messages)
        self.toolCards = try container.decode([ToolCardState].self, forKey: .toolCards)
        self.timelineItems = try container.decodeIfPresent([TranscriptTimelineItemSurface].self, forKey: .timelineItems)
            ?? messages.map(TranscriptTimelineItemSurface.message)
            + toolCards.map(TranscriptTimelineItemSurface.toolCard)
        self.thinking = try container.decodeIfPresent(TranscriptThinkingSurface.self, forKey: .thinking)
        self.emptyTitle = try container.decodeIfPresent(String.self, forKey: .emptyTitle)
            ?? "Ask QuillCode to inspect, edit, or run this project."
        self.emptySubtitle = try container.decodeIfPresent(String.self, forKey: .emptySubtitle)
            ?? "Use Auto for normal coding work, Review for manual gates, or Read-only for exploration."
        self.emptyStarterActions = try container.decodeIfPresent(
            [TranscriptStarterActionSurface].self,
            forKey: .emptyStarterActions
        ) ?? TranscriptStarterActionSurface.defaults
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messages, forKey: .messages)
        try container.encode(toolCards, forKey: .toolCards)
        try container.encode(timelineItems, forKey: .timelineItems)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encode(emptyTitle, forKey: .emptyTitle)
        try container.encode(emptySubtitle, forKey: .emptySubtitle)
        try container.encode(emptyStarterActions, forKey: .emptyStarterActions)
    }
}

public struct TranscriptStarterActionSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var prompt: String

    public init(id: String, title: String, subtitle: String, prompt: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.prompt = prompt
    }

    public static let defaults: [TranscriptStarterActionSurface] = [
        TranscriptStarterActionSurface(
            id: "review-changes",
            title: "Review changes",
            subtitle: "Find risks in the current diff",
            prompt: "Review the current git diff and call out risks, missing tests, and next steps."
        ),
        TranscriptStarterActionSurface(
            id: "run-tests",
            title: "Run tests",
            subtitle: "Pick the right validation",
            prompt: "Find and run the most relevant tests for this project."
        ),
        TranscriptStarterActionSurface(
            id: "explain-project",
            title: "Explain project",
            subtitle: "Map the important files",
            prompt: "Give me a concise map of this project and the most important files."
        )
    ]
}

public struct TranscriptThinkingSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var traceTitle: String
    public var traceLines: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        traceTitle: String = "Trace",
        traceLines: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.traceTitle = traceTitle
        self.traceLines = traceLines
    }
}

public enum TranscriptTimelineItemKind: String, Codable, Sendable {
    case message
    case toolCard
}

public struct TranscriptTimelineItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: TranscriptTimelineItemKind
    public var message: MessageSurface?
    public var toolCard: ToolCardState?

    public static func message(_ message: MessageSurface) -> TranscriptTimelineItemSurface {
        TranscriptTimelineItemSurface(
            id: "message-\(message.id.uuidString)",
            kind: .message,
            message: message
        )
    }

    public static func toolCard(_ toolCard: ToolCardState) -> TranscriptTimelineItemSurface {
        TranscriptTimelineItemSurface(
            id: "timeline-tool-\(toolCard.id)",
            kind: .toolCard,
            toolCard: toolCard
        )
    }
}

public struct ContextBannerSurface: Codable, Sendable, Hashable {
    public var usedPercent: Int
    public var title: String
    public var subtitle: String
    public var newThreadCommand: WorkspaceCommandSurface
    public var forkCommand: WorkspaceCommandSurface
    public var forkCommands: [WorkspaceCommandSurface]
    public var compactCommand: WorkspaceCommandSurface

    public init(
        usedPercent: Int,
        title: String,
        subtitle: String,
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
        self.newThreadCommand = newThreadCommand
        self.forkCommand = forkCommand
        self.forkCommands = Self.normalizedForkCommands(
            primary: forkCommand,
            commands: forkCommands
        )
        self.compactCommand = compactCommand
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case title
        case subtitle
        case newThreadCommand
        case forkCommand
        case forkCommands
        case compactCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUsedPercent = try container.decode(Int.self, forKey: .usedPercent)
        let decodedTitle = try container.decode(String.self, forKey: .title)
        let decodedSubtitle = try container.decode(String.self, forKey: .subtitle)
        let decodedNewThreadCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .newThreadCommand)
        let decodedForkCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .forkCommand)
        let decodedForkCommands = try container.decodeIfPresent([WorkspaceCommandSurface].self, forKey: .forkCommands)
        let decodedCompactCommand = try container.decodeIfPresent(WorkspaceCommandSurface.self, forKey: .compactCommand)
            ?? WorkspaceCommandSurface(
                id: "compact-context",
                title: "Compact context",
                category: WorkspaceCommandPalette.threadCategory,
                keywords: ["thread", "context", "summarize", "compact"],
                isEnabled: decodedForkCommand.isEnabled
            )
        self.usedPercent = decodedUsedPercent
        self.title = decodedTitle
        self.subtitle = decodedSubtitle
        self.newThreadCommand = decodedNewThreadCommand
        self.forkCommand = decodedForkCommand
        self.forkCommands = Self.normalizedForkCommands(
            primary: decodedForkCommand,
            commands: decodedForkCommands
        )
        self.compactCommand = decodedCompactCommand
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
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

public struct MessageSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var accessibilityLabel: String
    public var feedback: MessageFeedbackValue?

    public init(message: ChatMessage, feedback: MessageFeedbackValue? = nil) {
        self.id = message.id
        self.role = message.role
        self.text = message.content
        self.accessibilityLabel = "\(message.role.rawValue): \(message.content)"
        self.feedback = feedback
    }
}

public struct ComposerSurface: Codable, Sendable, Hashable {
    public var draft: String
    public var placeholder: String
    public var isSending: Bool
    public var canSend: Bool
    public var slashSuggestions: [SlashCommandSuggestionSurface]

    public init(composer: ComposerState) {
        self.draft = composer.draft
        self.placeholder = composer.placeholder
        self.isSending = composer.isSending
        self.canSend = !composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !composer.isSending
        self.slashSuggestions = SlashCommandCatalog.suggestions(for: composer.draft)
    }
}
