import Foundation
import QuillCodeCore
import QuillCodeTools

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
        self.fileMentionSuggestions = try container.decode(
            [FileMentionSuggestionSurface].self,
            forKey: .fileMentionSuggestions
        )
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
