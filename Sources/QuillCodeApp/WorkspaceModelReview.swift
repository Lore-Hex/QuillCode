import Foundation
import QuillCodeAgent
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

    /// Resolves an approval gate and, once it settles, drains any follow-ups the user queued while
    /// the gate was open. For a Plan-mode APPROVE it also resumes the agent so it drives the plan
    /// forward — proposing the next step, which is itself gated for approval (see
    /// `resumeAgentAfterApproval`). This is the SINGLE async path both the tests and the desktop
    /// drive for EVERY decided gate action — approve/approveAlways AND deny/denyAlways, in any mode
    /// (plan/auto/review) — so the queue drains after the gate is resolved regardless of the
    /// decision or mode. The resume and drain are pinned to the thread the held tool acted on, so a
    /// thread switch during the async continuation can never resume/drain the wrong plan.
    @discardableResult
    func approveToolCardAndResume(_ action: ToolCardActionSurface, workspaceRoot: URL) async -> Bool {
        let decidedThreadID = selectedThread?.id
        let request = WorkspaceApprovalActionPlanner.pendingRequest(id: action.requestID, in: selectedThread)
        let didRun = runToolCardAction(action, workspaceRoot: workspaceRoot)
        guard didRun, selectedThread?.id == decidedThreadID else { return didRun }

        // An APPROVE resumes the run: a spend-fuse approval resumes past the budget gate; a Plan-mode
        // approve resumes the plan (`resumeAgentAfterApproval` is guarded to Plan mode + the pinned
        // thread, so it no-ops for an auto/review approval). A DENY runs neither — it only resolved
        // the gate. After any resume settles we still drain (below), so the two paths agree.
        if action.kind.approvesHeldTool {
            if request?.scope == .runSpendFuse {
                await resumeAgentAfterSpendFuseApproval(workspaceRoot: workspaceRoot, expectedThreadID: decidedThreadID)
            } else {
                await resumeAgentAfterApproval(workspaceRoot: workspaceRoot, expectedThreadID: decidedThreadID)
            }
        }

        // Drain the follow-up queue after the gate is RESOLVED — for every decision (approve/deny)
        // and every mode/scope. `canDrainAfter` keeps this a no-op when a resumed plan hit the NEXT
        // gate (an undecided approval remains) or an `edit` left the gate open, so items never drain
        // past a still-open gate and never drain while a run is in flight. This is the common choke
        // point that fixes the deny/skip and auto/review-approve strandings the Plan-only resume
        // drain missed. Pinned to the decided thread so a mid-decision thread switch drains nothing
        // wrong.
        if let decidedThreadID {
            await drainFollowUpQueue(
                after: AgentTurnResult(threadID: decidedThreadID, completed: true),
                workspaceRoot: workspaceRoot,
                onStarted: nil,
                onProgressUpdated: nil
            )
        }
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

    /// Drains follow-ups after an approval gate DECISION was already recorded (e.g. a deny/skip whose
    /// decision the desktop recorded unconditionally so a refusal is never dropped). Runs the same
    /// self-gated drain as `approveToolCardAndResume` (a no-op while a run is in flight or an
    /// undecided approval remains), pinned to the decided thread. Separate from the decision so the
    /// safety-critical "record the refusal" can be unconditional while the drain stays slot-gated.
    func drainFollowUpQueueAfterGateDecision(threadID: UUID?, workspaceRoot: URL) async {
        await drainFollowUpQueueForThread(threadID, workspaceRoot: workspaceRoot)
    }

    /// Recovers a thread's follow-up queue that could not drain when it was first decided/finished
    /// because the single global `.send` slot was busy running ANOTHER thread. There is only one
    /// `.send` slot, so a deny on thread A while a run holds the slot for thread B skips A's drain,
    /// and B's own completion drains only B's queue — leaving A's queue stranded as visible chips.
    /// The desktop calls this for the now-idle thread when a thread becomes the active context
    /// (select) and when the `.send` slot frees (a send/approval finishes), so A's queue drains as
    /// soon as A is in front or the slot is free again — without needing two threads to run at once.
    /// `canDrainAfter`-gated, so it never drains past an open gate, never drains a running thread,
    /// and drains each item exactly once.
    func recoverFollowUpQueueIfIdle(threadID: UUID?, workspaceRoot: URL) async {
        guard !composer.isSending else { return }
        await drainFollowUpQueueForThread(threadID, workspaceRoot: workspaceRoot)
    }

    /// Shared self-gated drain of a single thread's follow-up queue: runs the `canDrainAfter`-gated
    /// `drainFollowUpQueue` pinned to `threadID` (a no-op while a run is in flight or an undecided
    /// approval remains on that thread).
    private func drainFollowUpQueueForThread(_ threadID: UUID?, workspaceRoot: URL) async {
        guard let threadID else { return }
        await drainFollowUpQueue(
            after: AgentTurnResult(threadID: threadID, completed: true),
            workspaceRoot: workspaceRoot,
            onStarted: nil,
            onProgressUpdated: nil
        )
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
            let result = runToolCall(plan.request.toolCall, workspaceRoot: workspaceRoot)
            if selectedThread?.mode == .plan {
                appendApprovedPlanToolFeedback(call: plan.request.toolCall, result: result)
            }
        } else {
            if let assistantNotice = plan.assistantNotice {
                appendAssistantNotice(assistantNotice)
            }
            if let thread = selectedThread {
                threadPersistence.save(thread)
            }
            refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        }

        // An "always" answer additionally persists a permission rule for this exact action +
        // resource, then backfills: every OTHER still-pending approval the new rule matches is
        // resolved the same way, so teaching the gate once clears the whole queue.
        if let ruleDecision = plan.persistRuleDecision {
            persistPermissionRuleAndBackfill(
                from: plan.request,
                decision: ruleDecision,
                workspaceRoot: workspaceRoot
            )
        }
        return true
    }

    private func appendApprovedPlanToolFeedback(call: ToolCall, result: ToolResult) {
        let feedback = AgentToolFeedback(toolCall: call, result: result, followUpResult: nil)
        let content = (try? JSONHelpers.encodePretty(feedback)) ?? "{}"
        mutateSelectedThread { thread in
            thread.messages.append(.init(role: .tool, content: content))
            thread.updatedAt = Date()
        }
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
