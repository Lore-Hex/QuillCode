import Foundation
import QuillCodeCore
import QuillCodeTools

@MainActor
public extension QuillCodeWorkspaceModel {
    func runReviewAction(_ action: WorkspaceReviewActionSurface, workspaceRoot: URL) {
        guard selectedThread != nil else { return }

        // A non-mutating action (e.g. Open) is a plain read: route it straight through
        // host.file.read so it does NOT pair a diff refresh or clear the review pane
        // (unlike the stage/restore mutating actions below). The planner also refuses
        // to pair a diff refresh for these, so the invariant holds even if this path moves.
        if !action.kind.isMutating {
            _ = runToolCall(
                ToolCall(
                    name: ToolDefinition.fileRead.name,
                    argumentsJSON: ToolArguments.json(["path": action.path])
                ),
                workspaceRoot: workspaceRoot
            )
            return
        }

        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let runPlan = WorkspaceReviewActionToolCallPlanner.runPlan(for: action)
        let result = WorkspaceReviewActionRunner(
            plan: runPlan,
            executor: WorkspaceToolCallExecutorFactory.executor(model: self, router: router)
        ).run()
        for recordedResult in result.recordedResults {
            appendToolRun(call: recordedResult.call, result: recordedResult.result)
        }

        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: result.finalStatus)
    }

    func runPullRequestReviewThreadAction(
        _ action: WorkspacePullRequestReviewThreadActionSurface,
        workspaceRoot: URL
    ) {
        guard selectedThread != nil else { return }
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let runPlan = WorkspacePullRequestReviewThreadActionToolCallPlanner.runPlan(for: action)
        let result = WorkspacePullRequestReviewThreadActionRunner(
            plan: runPlan,
            executor: WorkspaceToolCallExecutorFactory.executor(model: self, router: router)
        ).run()
        for recordedResult in result.recordedResults {
            appendToolRun(call: recordedResult.call, result: recordedResult.result)
        }

        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: result.finalStatus)
    }

    func runPullRequestReviewThreadReply(
        _ request: WorkspacePullRequestReviewThreadReplyRequest,
        workspaceRoot: URL
    ) {
        guard selectedThread != nil else { return }
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.running)

        let router = ToolRouter(workspaceRoot: workspaceRoot)
        let runPlan = WorkspacePullRequestReviewThreadReplyToolCallPlanner.runPlan(for: request)
        let result = WorkspacePullRequestReviewThreadReplyRunner(
            plan: runPlan,
            executor: WorkspaceToolCallExecutorFactory.executor(model: self, router: router)
        ).run()
        for recordedResult in result.recordedResults {
            appendToolRun(call: recordedResult.call, result: recordedResult.result)
        }

        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: result.finalStatus)
    }

    @discardableResult
    func runToolCardAction(_ action: ToolCardActionSurface, workspaceRoot: URL) -> Bool {
        guard let plan = WorkspaceApprovalActionPlanner.plan(action: action, thread: selectedThread) else {
            setLastError("Approval request is no longer available.")
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.failed)
            return false
        }

        if let composerDraft = plan.composerDraft {
            composer.draft = composerDraft
            setLastError(nil)
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
            return true
        }

        if let decisionEvent = plan.decisionEvent {
            mutateSelectedThread { thread in
                thread.events.append(decisionEvent)
            }
        }

        if plan.shouldRunTool {
            _ = runToolCall(plan.request.toolCall, workspaceRoot: workspaceRoot)
        } else {
            if let assistantNotice = plan.assistantNotice {
                appendAssistantNotice(assistantNotice)
            }
            if let thread = selectedThread {
                threadPersistence.save(thread)
            }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        }
        return true
    }

    @discardableResult
    func addReviewComment(path: String, text: String) -> Bool {
        addReviewComment(path: path, lineNumber: nil, endLineNumber: nil, lineKind: nil, text: text)
    }

    @discardableResult
    func addReviewComment(
        path: String,
        lineNumber: Int?,
        endLineNumber: Int? = nil,
        lineKind: WorkspaceReviewLineKind?,
        text: String
    ) -> Bool {
        guard selectedThread != nil,
              let event = WorkspaceReviewCommentPlanner.event(
                path: path,
                lineNumber: lineNumber,
                endLineNumber: endLineNumber,
                lineKind: lineKind,
                text: text,
                review: surface().review
              )
        else {
            return false
        }
        mutateSelectedThread { thread in
            thread.events.append(event)
        }
        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }
}

@MainActor
private extension QuillCodeWorkspaceModel {
    func appendToolRun(call: ToolCall, result: ToolResult) {
        mutateSelectedThread { thread in
            WorkspaceToolEventRecorder.append(call: call, result: result, to: &thread)
        }
    }

    func appendAssistantNotice(_ text: String) {
        mutateSelectedThread { thread in
            WorkspaceThreadNoticeAppender.appendAssistantNotice(text, to: &thread)
        }
    }
}
