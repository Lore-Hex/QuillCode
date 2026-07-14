import QuillCodeCore
import QuillCodeTools

struct WorkspaceReviewActionRunPlan: Sendable, Hashable {
    let actionCall: ToolCall
    /// `nil` for non-mutating actions (e.g. `.open`), which must not refresh the diff
    /// or clear the review pane.
    let diffRefreshCall: ToolCall?

    func finalStatus(actionResult: ToolResult, diffRefreshResult: ToolResult?) -> String {
        actionResult.ok && (diffRefreshResult?.ok ?? true)
            ? TopBarAgentStatusLabel.idle
            : TopBarAgentStatusLabel.failed
    }
}

enum WorkspaceReviewActionToolCallPlanner {
    static func runPlan(for action: WorkspaceReviewActionSurface) -> WorkspaceReviewActionRunPlan {
        let refreshSelection = WorkspaceReviewSelection(scope: action.scope)
        let diffRefreshCall: ToolCall?
        if action.kind.isMutating, let refreshSelection {
            diffRefreshCall = ToolCall(
                name: ToolDefinition.gitDiff.name,
                argumentsJSON: refreshSelection.gitDiffArgumentsJSON
            )
        } else {
            diffRefreshCall = nil
        }
        return WorkspaceReviewActionRunPlan(
            actionCall: toolCall(for: action),
            diffRefreshCall: diffRefreshCall
        )
    }

    static func toolCall(for action: WorkspaceReviewActionSurface) -> ToolCall {
        switch action.kind {
        case .open:
            // `.open` is dispatched as a non-mutating host.file.read; the plan pairs
            // no diff refresh (see runPlan), and the model short-circuits before here.
            return ToolCall(
                name: ToolDefinition.fileRead.name,
                argumentsJSON: ToolArguments.json(["path": action.path])
            )
        case .stage:
            return ToolCall(
                name: ToolDefinition.gitStage.name,
                argumentsJSON: ToolArguments.json(["path": action.path])
            )
        case .unstage:
            return ToolCall(
                name: ToolDefinition.gitRestore.name,
                argumentsJSON: ToolArguments.json([
                    "path": action.path,
                    "staged": true
                ])
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
        case .unstageHunk:
            return hunkToolCall(
                name: ToolDefinition.gitUnstageHunk.name,
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
