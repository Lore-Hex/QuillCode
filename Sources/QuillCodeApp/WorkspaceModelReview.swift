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

        // UI-initiated review actions run in the model's UI edit session, not any chat thread's.
        let router = ToolRouter(workspaceRoot: workspaceRoot, editGuard: uiEditSessionGuard)
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

        // UI-initiated review actions run in the model's UI edit session, not any chat thread's.
        let router = ToolRouter(workspaceRoot: workspaceRoot, editGuard: uiEditSessionGuard)
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

        // UI-initiated review actions run in the model's UI edit session, not any chat thread's.
        let router = ToolRouter(workspaceRoot: workspaceRoot, editGuard: uiEditSessionGuard)
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

    /// Runs the approval (the held tool) and, after a Plan-mode approval, resumes the agent so it
    /// drives the plan forward — proposing the next step, which is itself gated for approval (see
    /// `resumeAgentAfterApproval`). This is the SINGLE path both the tests and the desktop drive
    /// (the desktop wraps it in the cancellable `.send` slot), so the shipped wiring is exactly
    /// what is tested. The resume is pinned to the thread the held tool acted on, so a thread
    /// switch during the async continuation can never resume the wrong plan.
    @discardableResult
    func approveToolCardAndResume(_ action: ToolCardActionSurface, workspaceRoot: URL) async -> Bool {
        let approvedThreadID = selectedThread?.id
        let didRun = runToolCardAction(action, workspaceRoot: workspaceRoot)
        guard didRun, action.kind == .approve, selectedThread?.id == approvedThreadID else { return didRun }
        // `resumeAgentAfterApproval` is itself guarded to Plan mode + the pinned thread, so this
        // no-ops for a review/auto approval and only continues the approved plan.
        await resumeAgentAfterApproval(workspaceRoot: workspaceRoot, expectedThreadID: approvedThreadID)
        return didRun
    }

    /// Decide a blocked approval gate by its request id — the path the desktop uses to act on the
    /// "needs approval" notification's Approve/Skip buttons without opening the app. Routes through the
    /// exact same approval execution as the tool card (approve runs the held tool and resumes the plan;
    /// skip denies it), so async approval and in-app approval behave identically.
    @discardableResult
    func decidePendingApproval(requestID: String, approve: Bool, workspaceRoot: URL) async -> Bool {
        let action = ToolCardActionSurface(
            title: approve ? "Approve" : "Skip",
            kind: approve ? .approve : .deny,
            requestID: requestID,
            style: approve ? .primary : .secondary
        )
        return await approveToolCardAndResume(action, workspaceRoot: workspaceRoot)
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
            // Runs the approved tool directly (bypassing the gate) the same way every other
            // approved tool does. The thread mode is intentionally LEFT as-is: a Plan-mode
            // approval stays in Plan, so the resumed agent's next mutation is gated again
            // (the user approves each change) rather than flipping to autonomous execution.
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
