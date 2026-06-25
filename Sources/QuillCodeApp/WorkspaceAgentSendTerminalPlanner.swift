import QuillCodeCore

struct WorkspaceAgentSendCompletionPlan: Sendable {
    var thread: ChatThread
    var shouldRefreshMemoryContext: Bool
    var lifecycle: WorkspaceComposerSendLifecyclePlan
}

struct WorkspaceAgentSendTerminalPlan: Sendable {
    var lifecycle: WorkspaceComposerSendLifecyclePlan
}

enum WorkspaceAgentSendTerminalPlanner {
    static func completed(
        result: WorkspaceAgentSendSessionResult,
        composer: ComposerState
    ) -> WorkspaceAgentSendCompletionPlan {
        WorkspaceAgentSendCompletionPlan(
            thread: result.thread,
            shouldRefreshMemoryContext: result.savedMemory,
            lifecycle: WorkspaceComposerSendLifecycle.completed(from: composer)
        )
    }

    static func cancelled(composer: ComposerState) -> WorkspaceAgentSendTerminalPlan {
        WorkspaceAgentSendTerminalPlan(
            lifecycle: WorkspaceComposerSendLifecycle.cancelled(from: composer)
        )
    }

    static func failed(_ error: any Error, composer: ComposerState) -> WorkspaceAgentSendTerminalPlan {
        WorkspaceAgentSendTerminalPlan(
            lifecycle: WorkspaceComposerSendLifecycle.failed(error, from: composer)
        )
    }
}
