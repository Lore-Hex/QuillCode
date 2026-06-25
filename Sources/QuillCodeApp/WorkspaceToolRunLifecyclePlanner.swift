import QuillCodeCore

struct WorkspaceToolRunStartPlan: Sendable, Hashable {
    let lastError: String?
    let agentStatus: String
}

struct WorkspaceToolRunFinishPlan: Sendable, Hashable {
    let result: ToolResult
    let agentStatus: String
}

enum WorkspaceToolRunLifecyclePlanner {
    static func started() -> WorkspaceToolRunStartPlan {
        WorkspaceToolRunStartPlan(
            lastError: nil,
            agentStatus: TopBarAgentStatusLabel.running
        )
    }

    static func finished(execution: WorkspaceToolCallExecution) -> WorkspaceToolRunFinishPlan {
        WorkspaceToolRunFinishPlan(
            result: execution.primary.result,
            agentStatus: execution.ok
                ? TopBarAgentStatusLabel.idle
                : TopBarAgentStatusLabel.failed
        )
    }
}
