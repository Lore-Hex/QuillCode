import QuillCodeCore
import QuillCodeTools

enum WorkspaceReviewActionToolCallPlanner {
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
