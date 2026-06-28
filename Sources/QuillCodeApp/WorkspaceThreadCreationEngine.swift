import Foundation
import QuillCodeCore

struct WorkspaceThreadCreationContext: Sendable, Hashable {
    var projectID: UUID?
    var mode: AgentMode
    var model: String
    var instructions: [ProjectInstruction]
    var memories: [MemoryNote]

    init(
        projectID: UUID?,
        mode: AgentMode,
        model: String,
        instructions: [ProjectInstruction] = [],
        memories: [MemoryNote] = []
    ) {
        self.projectID = projectID
        self.mode = mode
        self.model = model
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
            instructions: context.instructions,
            memories: context.memories
        )
    }

    static func forkThread(
        from source: ChatThread,
        projectID: UUID?,
        strategy: WorkspaceThreadForkStrategy = .latestTurn
    ) -> ChatThread {
        ChatThread(
            title: "\(strategy.threadTitlePrefix): \(source.title)",
            projectID: projectID,
            mode: source.mode,
            model: source.model,
            messages: WorkspaceThreadSeedBuilder.forkSeedMessages(from: source, strategy: strategy),
            events: [
                .init(
                    kind: .notice,
                    summary: "\(strategy.noticeSummaryPrefix) from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
            instructions: source.instructions,
            memories: source.memories
        )
    }

    static func compactThread(from source: ChatThread, projectID: UUID?) -> ChatThread {
        ChatThread(
            title: "Compact: \(source.title)",
            projectID: projectID,
            mode: source.mode,
            model: source.model,
            messages: WorkspaceThreadSeedBuilder.compactSeedMessages(from: source),
            events: [
                .init(
                    kind: .notice,
                    summary: "Compacted context from \(source.title)",
                    payloadJSON: source.id.uuidString
                )
            ],
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
            messages: source.messages,
            events: source.events,
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
}
