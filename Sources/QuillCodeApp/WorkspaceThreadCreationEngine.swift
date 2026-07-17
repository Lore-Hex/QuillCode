import Foundation
import QuillCodeCore

struct WorkspaceThreadCreationContext: Sendable, Hashable {
    var projectID: UUID?
    var mode: AgentMode
    var model: String
    var personality: QuillCodePersonality
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]

    init(
        projectID: UUID?,
        mode: AgentMode,
        model: String,
        personality: QuillCodePersonality = .defaultValue,
        instructions: [ProjectInstruction] = [],
        memories: [MemoryNote] = []
    ) {
        self.projectID = projectID
        self.mode = mode
        self.model = model
        self.personality = personality
        self.instructions = instructions
        self.memories = memories
    }
}

struct WorkspaceThreadCreationEngine {
    static func newThread(context: WorkspaceThreadCreationContext) -> ChatThread {
        ChatThread(
            projectID: context.projectID,
            mode: context.mode,
            model: context.model,
            personality: context.personality,
            instructions: context.instructions,
            memories: context.memories
        )
    }

    static func forkThread(
        from source: ChatThread,
        projectID: UUID?,
        strategy: WorkspaceThreadForkStrategy = .latestTurn,
        summaryOverride: String? = nil
    ) -> ChatThread {
        ChatThread(
            title: "\(strategy.threadTitlePrefix): \(source.title)",
            projectID: projectID,
            mode: source.mode,
            model: source.model,
            personality: source.personality,
            messages: WorkspaceThreadSeedBuilder.forkSeedMessages(
                from: source,
                strategy: strategy,
                summaryOverride: summaryOverride
            ),
            events: [
                .init(
                    kind: .notice,
                    summary: "\(strategy.noticeSummaryPrefix) from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            goal: source.goal,
            instructions: source.instructions,
            memories: source.memories
        )
    }

    static func compactThread(
        from source: ChatThread,
        projectID: UUID?,
        summaryOverride: String? = nil
    ) -> ChatThread {
        ChatThread(
            title: "Compact: \(source.title)",
            projectID: projectID,
            mode: source.mode,
            model: source.model,
            personality: source.personality,
            messages: WorkspaceThreadSeedBuilder.compactSeedMessages(
                from: source,
                summaryOverride: summaryOverride
            ),
            events: [
                .init(
                    kind: .notice,
                    summary: "Compacted context from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            goal: source.goal,
            instructions: source.instructions,
            memories: source.memories
        )
    }

    static func duplicateThread(_ source: ChatThread, projectID: UUID?) -> ChatThread {
        var duplicate = ChatThread(
            title: "Copy: \(source.title)",
            projectID: projectID,
            mode: source.mode,
            model: source.model,
            personality: source.personality,
            messages: source.messages,
            events: source.events,
            goal: source.goal,
            isPinned: false,
            isArchived: false,
            instructions: source.instructions,
            memories: source.memories
        )
        duplicate.events.append(.init(
            kind: .notice,
            summary: "Duplicated from \(source.title)",
            payloadJSON: source.id.uuidString
        ))
        return duplicate
    }

    /// An incognito thread: session-only (never persisted — see ``ThreadRuntimeContext/isIncognito``)
    /// and pinned to the end-to-end-encrypted TrustedRouter route regardless of the workspace's
    /// selected model. Deliberately carries NO instructions/memories from the workspace: an incognito
    /// conversation neither reads from nor contributes to durable workspace context.
    static func incognitoThread(projectID: UUID?, mode: AgentMode) -> ChatThread {
        ChatThread(
            title: "Incognito",
            projectID: projectID,
            mode: mode,
            model: TrustedRouterDefaults.e2eModel,
            events: [
                .init(
                    kind: .notice,
                    summary: "Incognito chat: not saved, routed end-to-end encrypted"
                )
            ],
            runtimeContext: .incognito
        )
    }

    static func sideConversation(from source: ChatThread, projectID: UUID?) -> ChatThread {
        ChatThread(
            title: "Side: \(source.title)",
            projectID: projectID,
            mode: source.mode,
            model: source.model,
            personality: source.personality,
            messages: source.messages,
            events: [
                .init(
                    kind: .notice,
                    summary: "Side conversation from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories,
            worktree: source.worktree,
            pullRequest: source.pullRequest,
            runtimeContext: .sideConversation(parentThreadID: source.id)
        )
    }
}
