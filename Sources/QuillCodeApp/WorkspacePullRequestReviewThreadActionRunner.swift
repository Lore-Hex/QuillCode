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

struct WorkspacePullRequestReviewThreadReplyRunResult: Sendable, Hashable {
    let plan: WorkspacePullRequestReviewThreadReplyRunPlan
    let reply: WorkspaceRecordedToolResult
    let refresh: WorkspaceRecordedToolResult

    var recordedResults: [WorkspaceRecordedToolResult] {
        [reply, refresh]
    }

    var finalStatus: String {
        plan.finalStatus(
            replyResult: reply.result,
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

struct WorkspacePullRequestReviewThreadReplyRunner: Sendable {
    var plan: WorkspacePullRequestReviewThreadReplyRunPlan
    var executor: WorkspaceToolCallExecutor

    func run() -> WorkspacePullRequestReviewThreadReplyRunResult {
        let reply = WorkspaceRecordedToolResult(
            call: plan.replyCall,
            result: executor.executePrimary(plan.replyCall)
        )
        let refresh = WorkspaceRecordedToolResult(
            call: plan.refreshCall,
            result: executor.executePrimary(plan.refreshCall)
        )
        return WorkspacePullRequestReviewThreadReplyRunResult(
            plan: plan,
            reply: reply,
            refresh: refresh
        )
    }
}
