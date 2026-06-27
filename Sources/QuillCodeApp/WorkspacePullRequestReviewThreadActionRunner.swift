import QuillCodeCore

struct WorkspacePullRequestReviewThreadActionRunResult: Sendable, Hashable {
    let plan: WorkspacePullRequestReviewThreadActionRunPlan
    let action: WorkspaceRecordedToolResult
    let refresh: WorkspaceRecordedToolResult

    var recordedResults: [WorkspaceRecordedToolResult] {
        [action, refresh]
    }

    var finalStatus: String {
        plan.finalStatus(
            actionResult: action.result,
            refreshResult: refresh.result
        )
    }
}

struct WorkspacePullRequestReviewThreadActionRunner: Sendable {
    var plan: WorkspacePullRequestReviewThreadActionRunPlan
    var executor: WorkspaceToolCallExecutor

    func run() -> WorkspacePullRequestReviewThreadActionRunResult {
        let action = WorkspaceRecordedToolResult(
            call: plan.actionCall,
            result: executor.executePrimary(plan.actionCall)
        )
        let refresh = WorkspaceRecordedToolResult(
            call: plan.refreshCall,
            result: executor.executePrimary(plan.refreshCall)
        )
        return WorkspacePullRequestReviewThreadActionRunResult(
            plan: plan,
            action: action,
            refresh: refresh
        )
    }
}
