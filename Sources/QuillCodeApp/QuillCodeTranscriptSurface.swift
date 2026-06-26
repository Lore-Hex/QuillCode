import Foundation
import QuillCodeCore

public struct TranscriptSurface: Codable, Sendable, Hashable {
    public var messages: [MessageSurface]
    public var toolCards: [ToolCardState]
    public var timelineItems: [TranscriptTimelineItemSurface]
    public var thinking: TranscriptThinkingSurface?
    public var emptyTitle: String
    public var emptySubtitle: String

    public init(
        messages: [MessageSurface],
        toolCards: [ToolCardState],
        timelineItems: [TranscriptTimelineItemSurface]? = nil,
        thinking: TranscriptThinkingSurface? = nil,
        emptyTitle: String = "Ask QuillCode to inspect, edit, or run this project.",
        emptySubtitle: String = "Use Auto for normal coding work, Review for manual gates, or Read-only for exploration."
    ) {
        self.messages = messages
        self.toolCards = toolCards
        self.timelineItems = timelineItems ?? messages.map(TranscriptTimelineItemSurface.message)
            + toolCards.map(TranscriptTimelineItemSurface.toolCard)
        self.thinking = thinking
        self.emptyTitle = emptyTitle
        self.emptySubtitle = emptySubtitle
    }
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
    public var compactCommand: WorkspaceCommandSurface

    public init(
        usedPercent: Int,
        title: String,
        subtitle: String,
        newThreadCommand: WorkspaceCommandSurface,
        forkCommand: WorkspaceCommandSurface,
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
        self.compactCommand = compactCommand
    }

    private enum CodingKeys: String, CodingKey {
        case usedPercent
        case title
        case subtitle
        case newThreadCommand
        case forkCommand
        case compactCommand
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedUsedPercent = try container.decode(Int.self, forKey: .usedPercent)
        let decodedTitle = try container.decode(String.self, forKey: .title)
        let decodedSubtitle = try container.decode(String.self, forKey: .subtitle)
        let decodedNewThreadCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .newThreadCommand)
        let decodedForkCommand = try container.decode(WorkspaceCommandSurface.self, forKey: .forkCommand)
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
        self.compactCommand = decodedCompactCommand
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(newThreadCommand, forKey: .newThreadCommand)
        try container.encode(forkCommand, forKey: .forkCommand)
        try container.encode(compactCommand, forKey: .compactCommand)
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
