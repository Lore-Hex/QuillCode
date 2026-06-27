import QuillCodeCore
import QuillCodeTools

struct WorkspacePullRequestReviewThreadActionRunPlan: Sendable, Hashable {
    let actionCall: ToolCall
    let refreshCall: ToolCall

    func finalStatus(actionResult: ToolResult, refreshResult: ToolResult) -> String {
        actionResult.ok && refreshResult.ok
            ? TopBarAgentStatusLabel.idle
            : TopBarAgentStatusLabel.failed
    }
}

enum WorkspacePullRequestReviewThreadActionToolCallPlanner {
    static func runPlan(
        for action: WorkspacePullRequestReviewThreadActionSurface
    ) -> WorkspacePullRequestReviewThreadActionRunPlan {
        WorkspacePullRequestReviewThreadActionRunPlan(
            actionCall: toolCall(for: action),
            refreshCall: refreshCall(selector: action.selector)
        )
    }

    static func toolCall(for action: WorkspacePullRequestReviewThreadActionSurface) -> ToolCall {
        ToolCall(
            name: ToolDefinition.gitPullRequestReviewThread.name,
            argumentsJSON: ToolArguments.json([
                "threadId": action.threadID,
                "action": action.kind.rawValue
            ])
        )
    }

    private static func refreshCall(selector: String?) -> ToolCall {
        ToolCall(
            name: ToolDefinition.gitPullRequestReviewThreads.name,
            argumentsJSON: selector.map { ToolArguments.json(["selector": $0]) } ?? "{}"
        )
    }
}
