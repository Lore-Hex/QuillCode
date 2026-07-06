import Foundation

public struct ChatThread: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var projectID: UUID?
    public var instructions: [ProjectInstruction]
    public var memories: [MemoryNote]
    public var mode: AgentMode
    public var model: String
    public var messages: [ChatMessage]
    public var events: [ThreadEvent]
    public var isPinned: Bool
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Unsent text in the composer for this thread. Persisted separately from messages so a
    /// half-written prompt survives relaunch without becoming part of the transcript.
    public var composerDraft: String?
    /// Composer submissions entered while a run was active, parked as visible chips and
    /// drained one per turn boundary (see `FollowUpQueue`). Stored on the thread so the
    /// queue persists with the conversation and survives a reload; decodes to empty for
    /// threads written before this field existed.
    public var followUpQueue: [FollowUpItem]
    /// The git worktree this thread's runs operate in. nil = inherit the project root (every legacy
    /// thread, and any thread not bound to a fork worktree). See `WorktreeBinding`.
    public var worktree: WorktreeBinding?
    /// The thread this was forked from, for compare/land. nil when this thread was not forked.
    public var forkParentThreadID: UUID?
    /// The turn (a `TurnRevertPlan.turnMessageID`) a decision-point fork branched at. nil otherwise.
    public var forkAnchorTurnMessageID: UUID?

    public init(
        id: UUID = UUID(),
        title: String = "New chat",
        projectID: UUID? = nil,
        mode: AgentMode = .auto,
        model: String = TrustedRouterDefaults.defaultModel,
        messages: [ChatMessage] = [],
        events: [ThreadEvent] = [],
        isPinned: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        instructions: [ProjectInstruction] = [],
        memories: [MemoryNote] = [],
        composerDraft: String? = nil,
        followUpQueue: [FollowUpItem] = [],
        worktree: WorktreeBinding? = nil,
        forkParentThreadID: UUID? = nil,
        forkAnchorTurnMessageID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.instructions = instructions
        self.memories = memories
        self.mode = mode
        self.model = TrustedRouterDefaults.normalizedDefaultModelID(model)
        self.messages = messages
        self.events = events
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.composerDraft = composerDraft
        self.followUpQueue = followUpQueue
        self.worktree = worktree
        self.forkParentThreadID = forkParentThreadID
        self.forkAnchorTurnMessageID = forkAnchorTurnMessageID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case projectID
        case instructions
        case memories
        case mode
        case model
        case messages
        case events
        case isPinned
        case isArchived
        case createdAt
        case updatedAt
        case composerDraft
        case followUpQueue
        case worktree
        case forkParentThreadID
        case forkAnchorTurnMessageID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        self.instructions = try container.decodeIfPresent([ProjectInstruction].self, forKey: .instructions) ?? []
        self.memories = try container.decodeIfPresent([MemoryNote].self, forKey: .memories) ?? []
        self.mode = try container.decode(AgentMode.self, forKey: .mode)
        self.model = TrustedRouterDefaults.normalizedDefaultModelID(try container.decode(String.self, forKey: .model))
        self.messages = try container.decode([ChatMessage].self, forKey: .messages)
        self.events = try container.decode([ThreadEvent].self, forKey: .events)
        self.isPinned = try container.decode(Bool.self, forKey: .isPinned)
        self.isArchived = try container.decode(Bool.self, forKey: .isArchived)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.composerDraft = Self.normalizedComposerDraft(
            try container.decodeIfPresent(String.self, forKey: .composerDraft)
        )
        self.followUpQueue = try container.decodeIfPresent([FollowUpItem].self, forKey: .followUpQueue) ?? []
        self.worktree = try container.decodeIfPresent(WorktreeBinding.self, forKey: .worktree)
        self.forkParentThreadID = try container.decodeIfPresent(UUID.self, forKey: .forkParentThreadID)
        self.forkAnchorTurnMessageID = try container.decodeIfPresent(UUID.self, forKey: .forkAnchorTurnMessageID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(composerDraft, forKey: .composerDraft)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(memories, forKey: .memories)
        try container.encode(mode, forKey: .mode)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(events, forKey: .events)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(followUpQueue, forKey: .followUpQueue)
        try container.encodeIfPresent(worktree, forKey: .worktree)
        try container.encodeIfPresent(forkParentThreadID, forKey: .forkParentThreadID)
        try container.encodeIfPresent(forkAnchorTurnMessageID, forKey: .forkAnchorTurnMessageID)
    }

    private static func normalizedComposerDraft(_ draft: String?) -> String? {
        guard let draft,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return draft
    }
}
