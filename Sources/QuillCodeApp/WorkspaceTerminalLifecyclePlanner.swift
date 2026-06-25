import QuillCodeCore

struct WorkspaceTerminalLifecyclePlan: Sendable, Hashable {
    let lastError: String?
    let agentStatus: String
}

enum WorkspaceTerminalLifecyclePlanner {
    static func started() -> WorkspaceTerminalLifecyclePlan {
        WorkspaceTerminalLifecyclePlan(
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.terminal
        )
    }

    static func missingExecutionContext() -> WorkspaceTerminalLifecyclePlan {
        WorkspaceTerminalLifecyclePlan(
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.failed
        )
    }

    static func stopped() -> WorkspaceTerminalLifecyclePlan {
        WorkspaceTerminalLifecyclePlan(
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.stopped
        )
    }

    static func cancelled() -> WorkspaceTerminalLifecyclePlan {
        WorkspaceTerminalLifecyclePlan(
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.stopped
        )
    }

    static func finished(result: ToolResult) -> WorkspaceTerminalLifecyclePlan {
        WorkspaceTerminalLifecyclePlan(
            lastError: nil,
            agentStatus: result.ok
                ? TopBarAgentStatusLabel.idle
                : TopBarAgentStatusLabel.failed
        )
    }
}
