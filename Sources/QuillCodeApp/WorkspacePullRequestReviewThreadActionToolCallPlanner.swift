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
            refreshCall: WorkspacePullRequestReviewThreadRefreshToolCallPlanner.call(selector: action.selector)
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

}

struct WorkspacePullRequestReviewThreadReplyRunPlan: Sendable, Hashable {
    let replyCall: ToolCall
    let refreshCall: ToolCall

    func finalStatus(replyResult: ToolResult, refreshResult: ToolResult) -> String {
        replyResult.ok && refreshResult.ok
            ? TopBarAgentStatusLabel.idle
            : TopBarAgentStatusLabel.failed
    }
}

enum WorkspacePullRequestReviewThreadReplyToolCallPlanner {
    static func runPlan(
        for request: WorkspacePullRequestReviewThreadReplyRequest
    ) -> WorkspacePullRequestReviewThreadReplyRunPlan {
        WorkspacePullRequestReviewThreadReplyRunPlan(
            replyCall: toolCall(for: request),
            refreshCall: WorkspacePullRequestReviewThreadRefreshToolCallPlanner.call(selector: request.selector)
        )
    }

    static func toolCall(for request: WorkspacePullRequestReviewThreadReplyRequest) -> ToolCall {
        var arguments: [String: Any] = [
            "commentId": request.commentID,
            "body": request.body
        ]
        if let selector = normalizedSelector(request.selector) {
            arguments["selector"] = selector
        }
        return ToolCall(
            name: ToolDefinition.gitPullRequestReviewReply.name,
            argumentsJSON: ToolArguments.json(arguments)
        )
    }

    private static func normalizedSelector(_ selector: String?) -> String? {
        let trimmed = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum WorkspacePullRequestReviewThreadRefreshToolCallPlanner {
    static func call(selector: String?) -> ToolCall {
        let trimmedSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ToolCall(
            name: ToolDefinition.gitPullRequestReviewThreads.name,
            argumentsJSON: trimmedSelector.isEmpty ? "{}" : ToolArguments.json(["selector": trimmedSelector])
        )
    }
}
