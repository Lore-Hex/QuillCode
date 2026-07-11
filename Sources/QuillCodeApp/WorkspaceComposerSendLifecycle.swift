struct WorkspaceComposerSendLifecyclePlan: Equatable, Sendable {
    var composer: ComposerState
    var lastError: String?
    var agentStatus: String
}

enum WorkspaceComposerSendLifecycle {
    static func started(from composer: ComposerState) -> WorkspaceComposerSendLifecyclePlan {
        var nextComposer = composer
        nextComposer.draft = ""
        nextComposer.attachments = []
        nextComposer.isSending = true
        return WorkspaceComposerSendLifecyclePlan(
            composer: nextComposer,
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.running
        )
    }

    static func completed(from composer: ComposerState) -> WorkspaceComposerSendLifecyclePlan {
        var nextComposer = composer
        nextComposer.isSending = false
        return WorkspaceComposerSendLifecyclePlan(
            composer: nextComposer,
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.idle
        )
    }

    static func cancelled(from composer: ComposerState) -> WorkspaceComposerSendLifecyclePlan {
        var nextComposer = composer
        nextComposer.isSending = false
        return WorkspaceComposerSendLifecyclePlan(
            composer: nextComposer,
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.stopped
        )
    }

    static func failed(_ error: any Error, from composer: ComposerState) -> WorkspaceComposerSendLifecyclePlan {
        var nextComposer = composer
        nextComposer.isSending = false
        return WorkspaceComposerSendLifecyclePlan(
            composer: nextComposer,
            lastError: String(describing: error),
            agentStatus: TopBarAgentStatusLabel.failed
        )
    }
}
