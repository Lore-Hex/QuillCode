import QuillCodeCore

struct WorkspaceReviewActionRunResult: Sendable, Hashable {
    let plan: WorkspaceReviewActionRunPlan
    let action: WorkspaceRecordedToolResult
    let diffRefresh: WorkspaceRecordedToolResult

    var recordedResults: [WorkspaceRecordedToolResult] {
        [action, diffRefresh]
    }

    var finalStatus: String {
        plan.finalStatus(
            actionResult: action.result,
            diffRefreshResult: diffRefresh.result
        )
    }
}

struct WorkspaceReviewActionRunner: Sendable {
    var plan: WorkspaceReviewActionRunPlan
    var executor: WorkspaceToolCallExecutor

    func run() -> WorkspaceReviewActionRunResult {
        let action = WorkspaceRecordedToolResult(
            call: plan.actionCall,
            result: executor.executePrimary(plan.actionCall)
        )
        let diffRefresh = WorkspaceRecordedToolResult(
            call: plan.diffRefreshCall,
            result: executor.executePrimary(plan.diffRefreshCall)
        )
        return WorkspaceReviewActionRunResult(
            plan: plan,
            action: action,
            diffRefresh: diffRefresh
        )
    }
}
