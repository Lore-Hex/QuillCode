import Foundation
import QuillCodeCore
import QuillCodeTools

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
        emptySubtitle: String = "Use Auto for normal coding work, Review for manual gates, "
            + "or Read-only for exploration.",
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
            ?? "Use Auto for normal coding work, Review for manual gates, "
            + "or Read-only for exploration."
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
