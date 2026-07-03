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
    public var sentMessageHistory: [String]
    public var focusToken: Int
    public var planProgress: WorkspacePlanProgress?
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
