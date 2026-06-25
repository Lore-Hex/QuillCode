import QuillCodeCore

struct WorkspaceAgentSendCompletionPlan: Sendable {
    var thread: ChatThread
    var shouldRefreshMemoryContext: Bool
    var lifecycle: WorkspaceComposerSendLifecyclePlan
}

enum WorkspaceAgentSendCompletionPlanner {
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
}
