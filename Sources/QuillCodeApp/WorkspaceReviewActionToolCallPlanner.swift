import QuillCodeCore
import QuillCodeTools

struct WorkspaceReviewActionRunPlan: Sendable, Hashable {
    let actionCall: ToolCall
    let diffRefreshCall: ToolCall

    func finalStatus(actionResult: ToolResult, diffRefreshResult: ToolResult) -> String {
        actionResult.ok && diffRefreshResult.ok
            ? TopBarAgentStatusLabel.idle
            : TopBarAgentStatusLabel.failed
    }
}

enum WorkspaceReviewActionToolCallPlanner {
    static func runPlan(for action: WorkspaceReviewActionSurface) -> WorkspaceReviewActionRunPlan {
        WorkspaceReviewActionRunPlan(
            actionCall: toolCall(for: action),
            diffRefreshCall: ToolCall(name: ToolDefinition.gitDiff.name, argumentsJSON: "{}")
        )
    }

    static func toolCall(for action: WorkspaceReviewActionSurface) -> ToolCall {
        switch action.kind {
        case .stage:
            return ToolCall(
                name: ToolDefinition.gitStage.name,
                argumentsJSON: ToolArguments.json(["path": action.path])
            )
        case .restore:
            return ToolCall(
                name: ToolDefinition.gitRestore.name,
                argumentsJSON: ToolArguments.json(["path": action.path])
            )
        case .stageHunk:
            return hunkToolCall(
                name: ToolDefinition.gitStageHunk.name,
                action: action
            )
        case .restoreHunk:
            return hunkToolCall(
                name: ToolDefinition.gitRestoreHunk.name,
                action: action
            )
        }
    }

    private static func hunkToolCall(name: String, action: WorkspaceReviewActionSurface) -> ToolCall {
        ToolCall(
            name: name,
            argumentsJSON: ToolArguments.json([
                "path": action.path,
                "patch": action.patch ?? ""
            ])
        )
    }
}
