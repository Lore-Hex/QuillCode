import QuillCodeCore

struct WorkspaceReviewActionRunResult: Sendable, Hashable {
    let plan: WorkspaceReviewActionRunPlan
    let action: WorkspaceRecordedToolResult
    let diffRefresh: WorkspaceRecordedToolResult?

    var recordedResults: [WorkspaceRecordedToolResult] {
        [action] + (diffRefresh.map { [$0] } ?? [])
    }

    var finalStatus: String {
        plan.finalStatus(
            actionResult: action.result,
            diffRefreshResult: diffRefresh?.result
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
        let diffRefresh = plan.diffRefreshCall.map { call in
            WorkspaceRecordedToolResult(call: call, result: executor.executePrimary(call))
        }
        return WorkspaceReviewActionRunResult(
            plan: plan,
            action: action,
            diffRefresh: diffRefresh
        )
    }
}
