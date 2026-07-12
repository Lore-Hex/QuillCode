import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public func submitComposer(
        threadID: UUID? = nil,
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)? = nil,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async {
        // Run the typed turn, then drain the run thread's follow-up queue one item per turn
        // boundary — each queued item becomes the next turn. Draining inside this single
        // per-thread send task (the desktop coordinator holds that chat's slot for the whole call) keeps the
        // composer continuously "sending" across the wave, so no gap lets a stray idle submit
        // race the drain, and no double-send occurs (each item is popped exactly once).
        guard let first = await sendComposerDraftTurn(
            threadID: threadID,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        ) else { return }

        await drainFollowUpQueue(
            after: first,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        )
    }

    /// Drains queued follow-ups one per turn boundary, starting after `initialTurn` finished. Each
    /// item becomes the next turn through the shared run/finish machinery. The loop advances only
    /// when the just-finished turn is drainable (see `canDrainAfter`): a Stop, a failure, OR an
    /// UNDECIDED approval gate halts the wave and leaves the remaining queue intact and persisted.
    /// Shared by the composer submit path AND the single approval-decision choke point
    /// (`approveToolCardAndResume`), so a wave drains identically whether it started from a fresh
    /// submit or resumed after a gate was resolved — and never past an approval gate.
    func drainFollowUpQueue(
        after initialTurn: AgentTurnResult,
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)?,
        onProgressUpdated: (@MainActor @Sendable () -> Void)?
    ) async {
        var turn = initialTurn
        while canDrainAfter(turn), let queued = drainNextFollowUp(runThreadID: turn.threadID) {
            guard let nextTurn = await sendFollowUpTurn(
                queued,
                runThreadID: turn.threadID,
                workspaceRoot: workspaceRoot,
                onStarted: onStarted,
                onProgressUpdated: onProgressUpdated
            ) else { break }
            turn = nextTurn
        }
    }

    /// Whether the queue may drain after `turn`. A turn is drainable only when it COMPLETED
    /// normally, nothing is currently sending, AND the run thread has no undecided approval gate.
    /// A Stop/failure is not `completed`; a Plan-mode turn that proposes a mutating tool returns
    /// `.completed` but leaves an undecided `approvalRequested` — draining then would start a queued
    /// turn PAST the still-open gate (and orphan the held tool). The `isSending` check keeps the
    /// approval-decision drain a no-op while a resumed plan turn is still running. Reuses the same
    /// undecided-approval detection as the approval UI and the run-finished notification, so all
    /// paths agree.
    private func canDrainAfter(_ turn: AgentTurnResult) -> Bool {
        guard turn.completed, !agentRuns.isRunning(turn.threadID) else { return false }
        let runThread = root.threads.first { $0.id == turn.threadID }
        return WorkspaceApprovalActionPlanner.undecidedRequests(in: runThread).isEmpty
    }

    /// The disposition of one agent turn: the thread it ran on and whether it completed
    /// normally (vs. cancelled/failed). The drain loop keys off `completed` (and a separate
    /// pending-approval check) to decide whether to pull the next queued item.
    struct AgentTurnResult {
        var threadID: UUID
        var completed: Bool
    }

    /// Runs the turn for the current composer draft (a fresh user submit). Handles the
    /// ignore/slash/agent split exactly as before. Returns the turn result for the caller to
    /// drive the drain, or nil when nothing ran (empty draft, or a slash command, which has no
    /// queued follow-through).
    private func sendComposerDraftTurn(
        threadID requestedThreadID: UUID?,
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)?,
        onProgressUpdated: (@MainActor @Sendable () -> Void)?
    ) async -> AgentTurnResult? {
        let input = composerInput(for: requestedThreadID)
        let attachments = input.attachments
        let submissionPlan = WorkspaceComposerSubmissionPlanner.plan(
            draft: input.draft,
            hasAttachments: !attachments.isEmpty
        )
        let draftThreadID = input.threadID
        let prompt: String
        switch submissionPlan {
        case .ignore:
            return nil
        case .slash(let command, let originalPrompt):
            composer.draft = ""
            clearComposerDraft(for: draftThreadID)
            setLastError(nil)
            await handleSlashCommand(command, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
            return nil
        case .agent(let plannedPrompt):
            prompt = plannedPrompt
        }

        return await runAgentTurn(
            prompt: prompt,
            attachments: attachments,
            threadID: draftThreadID,
            clearingDraftFor: draftThreadID,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        )
    }

    /// Runs a drained follow-up item as the next turn on the owning run thread without changing
    /// the user's current selection. An already-deleted item never reaches here because
    /// `drainNextFollowUp` only returns items still present in the queue.
    private func sendFollowUpTurn(
        _ item: FollowUpItem,
        runThreadID: UUID,
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)?,
        onProgressUpdated: (@MainActor @Sendable () -> Void)?
    ) async -> AgentTurnResult? {
        return await runAgentTurn(
            prompt: item.text,
            attachments: item.attachments,
            threadID: runThreadID,
            clearingDraftFor: nil,
            workspaceRoot: workspaceRoot,
            onStarted: onStarted,
            onProgressUpdated: onProgressUpdated
        )
    }

    /// Shared per-turn engine: shapes the send-start plan, appends the user turn, marks the
    /// composer sending, runs the agent session, and applies the terminal lifecycle. Used for
    /// both a typed draft and a drained follow-up so both paths go through the identical
    /// run/finish machinery (no divergent lifecycle handling). Returns the turn result.
    @discardableResult
    private func runAgentTurn(
        prompt: String,
        attachments: [ChatAttachment] = [],
        threadID: UUID?,
        clearingDraftFor draftThreadID: UUID?,
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)?,
        onProgressUpdated: (@MainActor @Sendable () -> Void)?
    ) async -> AgentTurnResult? {
        guard let thread = prepareAgentSendThread(threadID: threadID) else { return nil }
        let sendStart = WorkspaceAgentSendStartPlanner.started(
            prompt: prompt,
            attachments: attachments,
            thread: thread,
            composer: composer
        )
        clearComposerDraft(for: draftThreadID)
        clearComposerAttachments(for: draftThreadID)
        var startedThread = sendStart.thread
        if let liveThread = root.threads.first(where: { $0.id == startedThread.id }) {
            startedThread.composerDraft = liveThread.composerDraft
            startedThread.composerAttachments = liveThread.composerAttachments
        }
        updateThreadFromAgentRun(startedThread)
        threadPersistence.save(startedThread)
        beginAgentRun(threadID: sendStart.threadID, lifecycle: sendStart.lifecycle)
        onStarted?()

        let outcome = await runAgentSession(
            sendStart,
            workspaceRoot: workspaceRoot,
            onProgressUpdated: onProgressUpdated
        )
        finishAgentSend(outcome, runThreadID: sendStart.threadID)
        if draftThreadID != nil, Self.normalizedComposerDraft(composer.draft) == nil {
            clearComposerDraft(for: draftThreadID)
        }
        return AgentTurnResult(threadID: sendStart.threadID, completed: outcome.didComplete)
    }

    private func prepareAgentSendThread(threadID: UUID?) -> ChatThread? {
        // Non-desktop callers may submit directly, so keep this fallback even though the desktop
        // materializes the first chat synchronously through `prepareComposerSubmissionThread()`.
        if threadID == nil, selectedThread == nil {
            _ = newChat()
        }
        let resolvedThreadID = threadID ?? root.selectedThreadID
        guard var thread = root.threads.first(where: { $0.id == resolvedThreadID }) else { return nil }
        syncThreadContext(into: &thread)
        return thread
    }

    private func composerInput(for requestedThreadID: UUID?) -> (
        threadID: UUID?,
        draft: String,
        attachments: [ChatAttachment]
    ) {
        let threadID = requestedThreadID ?? root.selectedThreadID
        guard let threadID, threadID != root.selectedThreadID else {
            return (threadID, composer.draft, composer.attachments)
        }
        guard let thread = root.threads.first(where: { $0.id == threadID }) else {
            return (threadID, "", [])
        }
        return (
            threadID,
            threadDrafts[threadID] ?? thread.composerDraft ?? "",
            thread.composerAttachments
        )
    }

    /// After a Plan-mode approval has run the held tool, resume the agent so it drives the plan
    /// forward instead of dead-stopping and forcing the user to hand-type "continue". The thread
    /// STAYS in Plan mode, so the resumed run only performs read-only investigation and the next
    /// mutating step is gated for approval again — one approval never authorizes an autonomous
    /// chain of unconfirmed mutations. The continuation adds no new user message; it carries the
    /// thread's most recent user message as intent (never an empty/stale prompt) and is bounded
    /// by the agent's `maxToolSteps`.
    public func resumeAgentAfterApproval(workspaceRoot: URL, expectedThreadID: UUID?) async {
        guard let expectedThreadID,
              !agentRuns.isRunning(expectedThreadID),
              let thread = root.threads.first(where: { $0.id == expectedThreadID }),
              thread.mode == .plan
        else { return }
        // Only resume when the user actually has a request on record to continue.
        guard let intentMessage = thread.messages.last(where: { $0.role == .user }),
              !intentMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !intentMessage.attachments.isEmpty
        else { return }
        let intent = intentMessage.content

        let sendStart = WorkspaceAgentSendStartPlan(
            prompt: intent,
            thread: thread,
            threadID: thread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: composer)
        )
        beginAgentRun(threadID: sendStart.threadID, lifecycle: sendStart.lifecycle)
        let outcome = await runAgentSession(sendStart, workspaceRoot: workspaceRoot)
        finishAgentSend(outcome, runThreadID: sendStart.threadID)
        // NOTE: the follow-up drain is NOT here — it runs at the single approval-decision choke
        // point (`approveToolCardAndResume`), which fires after EVERY gate resolution (approve/deny,
        // any mode), so this Plan-mode resume path and the deny/auto/review paths all drain once and
        // identically. Draining here too would double-drain the Plan-approve case.
    }

    public func resumeAgentAfterSpendFuseApproval(workspaceRoot: URL, expectedThreadID: UUID?) async {
        guard let expectedThreadID,
              !agentRuns.isRunning(expectedThreadID),
              let thread = root.threads.first(where: { $0.id == expectedThreadID })
        else {
            return
        }
        guard let intentMessage = thread.messages.last(where: { $0.role == .user }),
              !intentMessage.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !intentMessage.attachments.isEmpty
        else { return }
        let intent = intentMessage.content

        let sendStart = WorkspaceAgentSendStartPlan(
            prompt: intent,
            thread: thread,
            threadID: thread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: composer)
        )
        beginAgentRun(threadID: sendStart.threadID, lifecycle: sendStart.lifecycle)
        let outcome = await runAgentSession(sendStart, workspaceRoot: workspaceRoot)
        finishAgentSend(outcome, runThreadID: sendStart.threadID)
    }

    private func finishCompletedSend(
        _ result: WorkspaceAgentSendSessionResult,
        runThreadID: UUID
    ) throws {
        let completion = WorkspaceAgentSendTerminalPlanner.completed(
            result: result,
            composer: composer
        )
        var thread = completion.thread
        if completion.shouldRefreshMemoryContext {
            refreshThreadMemoryContext(&thread)
        }
        // These fields are model-owned: the agent's completion copy carries a stale snapshot
        // (captured at send-start). `updateThreadFromAgentRun` preserves the live values in memory;
        // carry those same values onto the copy we persist so disk matches memory.
        if let liveThread = root.threads.first(where: { $0.id == thread.id }) {
            thread.followUpQueue = liveThread.followUpQueue
            thread.composerDraft = liveThread.composerDraft
            thread.composerAttachments = liveThread.composerAttachments
        }
        updateThreadFromAgentRun(thread)
        try threadPersistence.saveOrThrow(thread)
        if let workspaceRoot = workspaceRoot(forThreadID: runThreadID) {
            _ = reconcileManagedWorktreeBranch(threadID: runThreadID, workspaceRoot: workspaceRoot)
        }
        // A completed run may have created, moved, or deleted files; keep composer
        // `@` mentions current for the selected local project without a manual refresh.
        if root.selectedThreadID == runThreadID {
            refreshFileMentionIndex()
        }
        finishAgentRun(threadID: runThreadID, lifecycle: completion.lifecycle)
    }

    private func finishAgentSend(_ outcome: WorkspaceAgentSendTaskOutcome, runThreadID: UUID) {
        switch outcome {
        case .completed(let result):
            do {
                try finishCompletedSend(result, runThreadID: runThreadID)
            } catch {
                finishFailedSend(error, runThreadID: runThreadID)
            }
        case .cancelled(let cancellation):
            finishCancelledSend(
                userPrompt: cancellation.userPrompt,
                threadID: cancellation.threadID,
                runThreadID: runThreadID
            )
        case .failed(let error):
            finishFailedSend(error, runThreadID: runThreadID)
        }
        // Surface any self-heal that happened during the run, pinned to the RUN's thread — not whatever
        // thread happens to be selected now, so a mid-run thread switch never misattributes the notice.
        drainSelfHealingNotices(expectedThreadID: runThreadID)
        // Stamp the run-integrity verdict onto the run's thread (persisted, so the Activity badge is
        // stable across reloads) BEFORE the finish notification reads it back.
        recordRunIntegrityIfNeeded(outcome: outcome, expectedThreadID: runThreadID)
        notifyRunFinishedIfNeeded(outcome: outcome, threadID: runThreadID)
    }

    func applyAgentProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard let progress = WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: expectedThreadID,
            composer: composer
        ) else { return }
        updateThreadFromAgentRun(progress.thread)
        updateAgentRun(threadID: expectedThreadID, status: progress.agentStatus)
    }

    private func finishCancelledSend(userPrompt: String, threadID: UUID, runThreadID: UUID) {
        let terminal = WorkspaceAgentSendTerminalPlanner.cancelled(composer: composer)
        mutateThread(threadID) { thread in
            WorkspaceComposerCancellationPlanner.applyCancelledSend(userPrompt: userPrompt, to: &thread)
        }
        finishAgentRun(threadID: runThreadID, lifecycle: terminal.lifecycle)
    }

    private func finishFailedSend(_ error: any Error, runThreadID: UUID) {
        let terminal = WorkspaceAgentSendTerminalPlanner.failed(error, composer: composer)
        finishAgentRun(threadID: runThreadID, lifecycle: terminal.lifecycle)
    }

    func applyComposerSendLifecycle(_ plan: WorkspaceComposerSendLifecyclePlan) {
        composer = plan.composer
        setLastError(plan.lastError)
        refreshTopBar(agentStatus: plan.agentStatus)
    }

    private func syncThreadContext(into thread: inout ChatThread) {
        // Existing chats own their project context. A background run must never inherit whichever
        // project the user happened to select after launching it.
        let projectID = thread.projectID
        refreshProjectMetadata(projectID)
        _ = WorkspaceThreadContextPreparer.syncThreadContext(
            &thread,
            fallbackProjectID: projectID,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }
}
