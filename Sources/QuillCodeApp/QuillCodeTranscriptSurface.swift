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
        case progress
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
        let decodedProgress = try container.decodeIfPresent(ContextBannerProgressSurface.self, forKey: .progress)
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
        self.progress = decodedProgress
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

public struct MessageSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var accessibilityLabel: String
    public var feedback: MessageFeedbackValue?
    /// Present on the user message that began a turn whose `apply_patch` edits can be
    /// reverted, so the UI can offer a "Revert this turn's edits" affordance there.
    public var revert: MessageRevertSurface?

    public init(message: ChatMessage, feedback: MessageFeedbackValue? = nil, revert: MessageRevertSurface? = nil) {
        self.id = message.id
        self.role = message.role
        self.text = message.content
        self.accessibilityLabel = "\(message.role.rawValue): \(message.content)"
        self.feedback = feedback
        self.revert = revert
    }
}

/// The revert affordance for a turn: which turn to revert, and whether the turn also made
/// edits outside `apply_patch` (so the UI can disclose what the revert cannot undo).
public struct MessageRevertSurface: Codable, Sendable, Hashable {
    public var turnMessageID: UUID
    public var hasNonApplyPatchEdits: Bool

    public init(turnMessageID: UUID, hasNonApplyPatchEdits: Bool) {
        self.turnMessageID = turnMessageID
        self.hasNonApplyPatchEdits = hasNonApplyPatchEdits
    }
}

/// The single source of truth for the revert affordance's user-facing copy, so the native,
/// HTML, and harness surfaces make byte-identical, truthful claims about what a reverse-patch
/// revert does and does NOT undo.
public enum TurnRevertCopy {
    public static let buttonTitle = "Revert this turn's edits"

    public static func scope(hasNonApplyPatchEdits: Bool) -> String {
        var text = [
            "Reverses the file edits this turn applied, including files it created.",
            "It does not undo your own earlier edits, shell commands the turn ran, or git commits."
        ].joined(separator: " ")
        if hasNonApplyPatchEdits {
            text += " This turn also changed files outside apply_patch, which can't be reverted automatically."
        }
        return text
    }
}

public struct ComposerSurface: Codable, Sendable, Hashable {
    public var draft: String
    public var placeholder: String
    public var isSending: Bool
    public var canSend: Bool
    public var slashSuggestions: [SlashCommandSuggestionSurface]
    public var fileMentionSuggestions: [FileMentionSuggestionSurface]
    /// Previously sent user messages (oldest first) for Up/Down history recall.
    public var sentMessageHistory: [String]
    /// Bumped by the `focus-composer` command; the view focuses the input when it changes.
    public var focusToken: Int
    /// The current run's plan progress for the always-visible strip above the input. nil ⇒ no plan ⇒
    /// the strip renders nothing (a plan-less session looks byte-identical). Optional, so it decodes
    /// safely from surfaces persisted before this field existed.
    public var planProgress: WorkspacePlanProgress?
    /// Composer submissions entered during the live run, shown as delete-able chips above the
    /// input and drained one per turn boundary. Empty when there is nothing queued.
    public var followUpQueue: [FollowUpItemSurface]

    public init(
        composer: ComposerState,
        fileMentionIndex: WorkspaceFileIndex = WorkspaceFileIndex(),
        changedFilePaths: Set<String> = [],
        sentMessageHistory: [String] = [],
        planProgress: WorkspacePlanProgress? = nil,
        followUpQueue: [FollowUpItem] = []
    ) {
        self.draft = composer.draft
        self.placeholder = composer.placeholder
        self.isSending = composer.isSending
        // Sendable even while a run is in flight: a non-empty draft can always be submitted —
        // it enqueues as a follow-up chip when sending, and sends immediately when idle. The
        // composer never locks, so `canSend` no longer gates on `isSending`.
        self.canSend = !composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.slashSuggestions = SlashCommandCatalog.suggestions(for: composer.draft)
        self.fileMentionSuggestions = FileMentionCatalog.suggestions(
            for: composer.draft,
            in: fileMentionIndex,
            changedPaths: changedFilePaths
        )
        self.sentMessageHistory = sentMessageHistory
        self.focusToken = composer.focusToken
        self.planProgress = planProgress
        self.followUpQueue = followUpQueue.map(FollowUpItemSurface.init)
    }

    private enum CodingKeys: String, CodingKey {
        case draft, placeholder, isSending, canSend
        case slashSuggestions, fileMentionSuggestions, sentMessageHistory, focusToken
        case planProgress, followUpQueue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.draft = try container.decode(String.self, forKey: .draft)
        self.placeholder = try container.decode(String.self, forKey: .placeholder)
        self.isSending = try container.decode(Bool.self, forKey: .isSending)
        self.canSend = try container.decode(Bool.self, forKey: .canSend)
        self.slashSuggestions = try container.decode([SlashCommandSuggestionSurface].self, forKey: .slashSuggestions)
        self.fileMentionSuggestions = try container.decode([FileMentionSuggestionSurface].self, forKey: .fileMentionSuggestions)
        self.sentMessageHistory = try container.decode([String].self, forKey: .sentMessageHistory)
        self.focusToken = try container.decode(Int.self, forKey: .focusToken)
        // Both optional-add fields decode safely from surfaces persisted before they existed.
        self.planProgress = try container.decodeIfPresent(WorkspacePlanProgress.self, forKey: .planProgress)
        self.followUpQueue = try container.decodeIfPresent([FollowUpItemSurface].self, forKey: .followUpQueue) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(draft, forKey: .draft)
        try container.encode(placeholder, forKey: .placeholder)
        try container.encode(isSending, forKey: .isSending)
        try container.encode(canSend, forKey: .canSend)
        try container.encode(slashSuggestions, forKey: .slashSuggestions)
        try container.encode(fileMentionSuggestions, forKey: .fileMentionSuggestions)
        try container.encode(sentMessageHistory, forKey: .sentMessageHistory)
        try container.encode(focusToken, forKey: .focusToken)
        try container.encodeIfPresent(planProgress, forKey: .planProgress)
        try container.encode(followUpQueue, forKey: .followUpQueue)
    }
}

/// A single queued follow-up rendered as a composer chip. Carries the id (for the delete
/// affordance's target) and the text (the chip label / accessibility).
public struct FollowUpItemSurface: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var text: String

    public init(_ item: FollowUpItem) {
        self.id = item.id
        self.text = item.text
    }

    public init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}
