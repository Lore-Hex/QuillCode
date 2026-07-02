import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    public var canRetryLastUserTurn: Bool {
        WorkspaceRetryPlanner.canRetryLastUserTurn(
            in: selectedThread,
            isSending: composer.isSending
        )
    }

    public func setDraft(_ draft: String) {
        composer.draft = draft
    }

    @discardableResult
    public func prepareRetryLastUserTurn() -> Bool {
        guard let draft = WorkspaceRetryPlanner.retryDraft(in: selectedThread) else {
            return false
        }
        composer.draft = draft
        setLastError(nil)
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
        return true
    }

    public func submitComposer(
        workspaceRoot: URL,
        onStarted: (@MainActor @Sendable () -> Void)? = nil,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async {
        let submissionPlan = WorkspaceComposerSubmissionPlanner.plan(draft: composer.draft)
        let draftThreadID = root.selectedThreadID
        let prompt: String
        switch submissionPlan {
        case .ignore:
            return
        case .slash(let command, let originalPrompt):
            composer.draft = ""
            threadDrafts = ComposerDraftStore.cleared(draftThreadID, drafts: threadDrafts)
            setLastError(nil)
            await handleSlashCommand(command, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
            return
        case .agent(let plannedPrompt):
            prompt = plannedPrompt
        }

        guard let thread = prepareAgentSendThread() else { return }
        let sendStart = WorkspaceAgentSendStartPlanner.started(
            prompt: prompt,
            thread: thread,
            composer: composer
        )
        updateThreadFromAgentRun(sendStart.thread)
        threadPersistence.save(sendStart.thread)
        applyComposerSendLifecycle(sendStart.lifecycle)
        threadDrafts = ComposerDraftStore.cleared(draftThreadID, drafts: threadDrafts)
        onStarted?()

        let outcome = await runAgentSession(sendStart, workspaceRoot: workspaceRoot, onProgressUpdated: onProgressUpdated)
        finishAgentSend(outcome, runThreadID: sendStart.threadID)
    }

    private func prepareAgentSendThread() -> ChatThread? {
        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return nil }
        syncThreadContext(into: &thread)
        return thread
    }

    /// Runs one agent send through the shared coordinator and returns its typed outcome (the
    /// caller passes it to `finishAgentSend`). Used by both `submitComposer` (a fresh user turn)
    /// and `resumeAgentAfterApproval` (a continuation that adds no user message).
    /// `recordsUserMessage: false` because the caller has already shaped the thread (a user turn
    /// was appended for a submit; nothing is appended for a resume).
    func runAgentSession(
        _ sendStart: WorkspaceAgentSendStartPlan,
        workspaceRoot: URL,
        onProgressUpdated: (@MainActor @Sendable () -> Void)? = nil
    ) async -> WorkspaceAgentSendTaskOutcome {
        let session = agentSendSessionFactory(workspaceRoot: workspaceRoot)
            .makeSession(
                prompt: sendStart.prompt,
                thread: sendStart.thread,
                recordsUserMessage: false
            )
        return await WorkspaceAgentSendTaskCoordinator(
            start: sendStart,
            session: session
        ).run { [weak self] progressThread in
            await self?.applyAgentProgress(progressThread, expectedThreadID: sendStart.threadID)
            await onProgressUpdated?()
        }
    }

    /// After a Plan-mode approval has run the held tool, resume the agent so it drives the plan
    /// forward instead of dead-stopping and forcing the user to hand-type "continue". The thread
    /// STAYS in Plan mode, so the resumed run only performs read-only investigation and the next
    /// mutating step is gated for approval again — one approval never authorizes an autonomous
    /// chain of unconfirmed mutations. The continuation adds no new user message; it carries the
    /// thread's most recent user message as intent (never an empty/stale prompt) and is bounded
    /// by the agent's `maxToolSteps`.
    public func resumeAgentAfterApproval(workspaceRoot: URL, expectedThreadID: UUID?) async {
        // Pinned to the approved thread: if the user switched threads since approving, the still
        // -selected thread won't match, so we never continue a different plan.
        guard !composer.isSending, let thread = selectedThread,
              thread.id == expectedThreadID, thread.mode == .plan else { return }
        // Only resume when the user actually has a request on record to continue.
        guard let intent = thread.messages.last(where: { $0.role == .user })?.content,
              !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let sendStart = WorkspaceAgentSendStartPlan(
            prompt: intent,
            thread: thread,
            threadID: thread.id,
            lifecycle: WorkspaceComposerSendLifecycle.started(from: composer)
        )
        applyComposerSendLifecycle(sendStart.lifecycle)
        let outcome = await runAgentSession(sendStart, workspaceRoot: workspaceRoot)
        finishAgentSend(outcome, runThreadID: sendStart.threadID)
    }

    private func agentSendSessionFactory(workspaceRoot: URL) -> WorkspaceAgentSendSessionFactory {
        WorkspaceAgentSendSessionFactory(
            baseRunner: runner,
            selectedProject: selectedProject,
            config: root.config,
            browser: browser,
            browserToolOverride: WorkspaceBrowserAgentToolOverride.make { [weak self] call, workspaceRoot in
                guard let self else { return nil }
                return self.executeBrowserToolForAgent(call, workspaceRoot: workspaceRoot)
            },
            computerUseBackend: computerUseBackend,
            globalMemoryDirectory: globalMemoryDirectory,
            mcpToolDefinitions: mcpRuntime.toolDefinitions(
                manifests: selectedProject?.extensionManifests ?? [],
                extensions: extensions
            ),
            mcpToolExecutionOverride: mcpRuntime.executionOverride(extensions: extensions),
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            workspaceRoot: workspaceRoot
        )
    }

    private func finishCompletedSend(_ result: WorkspaceAgentSendSessionResult) throws {
        let completion = WorkspaceAgentSendTerminalPlanner.completed(
            result: result,
            composer: composer
        )
        var thread = completion.thread
        if completion.shouldRefreshMemoryContext {
            refreshThreadMemoryContext(&thread)
        }
        updateThreadFromAgentRun(thread)
        try threadPersistence.saveOrThrow(thread)
        // A completed run may have created, moved, or deleted files; keep composer
        // `@` mentions current for the selected local project without a manual refresh.
        refreshFileMentionIndex()
        applyComposerSendLifecycle(completion.lifecycle)
    }

    private func finishAgentSend(_ outcome: WorkspaceAgentSendTaskOutcome, runThreadID: UUID) {
        switch outcome {
        case .completed(let result):
            do {
                try finishCompletedSend(result)
            } catch {
                finishFailedSend(error)
            }
        case .cancelled(let cancellation):
            finishCancelledSend(
                userPrompt: cancellation.userPrompt,
                threadID: cancellation.threadID
            )
        case .failed(let error):
            finishFailedSend(error)
        }
        // Surface any self-heal that happened during the run, pinned to the RUN's thread — not whatever
        // thread happens to be selected now, so a mid-run thread switch never misattributes the notice.
        drainSelfHealingNotices(expectedThreadID: runThreadID)
        notifyRunFinishedIfNeeded(outcome: outcome)
    }

    private func applyAgentProgress(_ thread: ChatThread, expectedThreadID: UUID) {
        guard let progress = WorkspaceAgentSendProgressPlanner.progress(
            thread: thread,
            expectedThreadID: expectedThreadID,
            composer: composer
        ) else { return }
        updateThreadFromAgentRun(progress.thread)
        composer = progress.composer
        setLastError(progress.lastError)
        refreshTopBar(agentStatus: progress.agentStatus)
    }

    /// Turns any self-heals the retry decorator performed during the run (recorded off the main actor)
    /// into visible "Self-healing" thread notices on the run's thread. Drained once the run ends —
    /// NOT per progress tick, because each tick's `updateThreadFromAgentRun` replaces the thread with
    /// the agent's authoritative copy and would clobber a model-appended notice. The channel is always
    /// drained so a stale event never bleeds into a later run; the notices are appended only when the
    /// run's thread is still selected (a thread switch drops them — they are purely informational).
    func drainSelfHealingNotices(expectedThreadID: UUID?) {
        guard let channel = retryEventChannel else { return }
        let events = channel.drain()
        guard !events.isEmpty,
              let thread = selectedThread,
              thread.id == expectedThreadID
        else { return }
        mutateSelectedThread { thread in
            for event in events {
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: SelfHealingNoticePlanner.noticeSummary(attempt: event.attempt, kind: event.kind)
                ))
            }
        }
        if let thread = selectedThread {
            threadPersistence.save(thread)
        }
    }

    private func executeBrowserToolForAgent(_ call: ToolCall, workspaceRoot: URL) -> ToolResult? {
        let result = mutateBrowserState { browser, lastError in
            WorkspaceBrowserToolExecutor.execute(
                call,
                workspaceRoot: workspaceRoot,
                browser: &browser,
                lastError: &lastError
            )
        }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return result
    }

    private func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) async {
        let action = WorkspaceSlashCommandDispatchPlanner.action(
            for: command,
            userText: originalPrompt,
            statusText: statusText()
        )
        await runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)
        composer.isSending = false
        refreshTopBar(agentStatus: Task.isCancelled
            ? TopBarAgentStatusLabel.stopped
            : TopBarAgentStatusLabel.idle
        )
    }

    func runThreadFollowUpSlashCommand(_ scheduleText: String, originalPrompt: String) {
        appendScheduledAutomationTranscript(
            createThreadFollowUpAutomation(matching: scheduleText),
            success: {
                WorkspaceSlashCommandTranscriptPlanner.threadFollowUpScheduled(
                    userText: originalPrompt,
                    scheduleDescription: $0
                )
            },
            failure: {
                WorkspaceSlashCommandTranscriptPlanner.threadFollowUpFailed(
                    userText: originalPrompt,
                    message: $0
                )
            }
        )
    }

    func runWorkspaceScheduleSlashCommand(_ scheduleText: String, originalPrompt: String) {
        appendScheduledAutomationTranscript(
            createWorkspaceScheduleAutomation(matching: scheduleText),
            success: {
                WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleScheduled(
                    userText: originalPrompt,
                    scheduleDescription: $0
                )
            },
            failure: {
                WorkspaceSlashCommandTranscriptPlanner.workspaceScheduleFailed(
                    userText: originalPrompt,
                    message: $0
                )
            }
        )
    }

    private func appendScheduledAutomationTranscript(
        _ automation: QuillAutomation?,
        success: (String) -> WorkspaceLocalCommandTranscript,
        failure: (String?) -> WorkspaceLocalCommandTranscript
    ) {
        let transcript = automation
            .map { success($0.scheduleDescription) }
            ?? failure(lastError)
        appendLocalCommandTranscript(transcript)
    }

    func appendLocalCommandTranscript(_ transcript: WorkspaceLocalCommandTranscript) {
        if selectedThread == nil {
            _ = newChat()
        }
        mutateSelectedThread { thread in
            WorkspaceLocalCommandTranscriptAppender.append(transcript, to: &thread)
        }
    }

    private func finishCancelledSend(userPrompt: String, threadID: UUID) {
        let terminal = WorkspaceAgentSendTerminalPlanner.cancelled(composer: composer)
        mutateThread(threadID) { thread in
            WorkspaceComposerCancellationPlanner.applyCancelledSend(userPrompt: userPrompt, to: &thread)
        }
        applyComposerSendLifecycle(terminal.lifecycle)
    }

    private func finishFailedSend(_ error: any Error) {
        let terminal = WorkspaceAgentSendTerminalPlanner.failed(error, composer: composer)
        applyComposerSendLifecycle(terminal.lifecycle)
    }

    private func applyComposerSendLifecycle(_ plan: WorkspaceComposerSendLifecyclePlan) {
        composer = plan.composer
        setLastError(plan.lastError)
        refreshTopBar(agentStatus: plan.agentStatus)
    }

    private func statusText() -> String {
        WorkspaceStatusTextBuilder.statusText(for: WorkspaceStatusContextBuilder.context(
            root: root,
            selectedProject: selectedProject,
            selectedThread: selectedThread,
            fallbackThreadContext: workspaceThreadContext(root.selectedProjectID)
        ))
    }

    private func syncThreadContext(into thread: inout ChatThread) {
        let projectID = thread.projectID ?? root.selectedProjectID
        refreshProjectMetadata(projectID)
        _ = WorkspaceThreadContextPreparer.syncThreadContext(
            &thread,
            fallbackProjectID: root.selectedProjectID,
            projects: root.projects,
            globalMemories: root.globalMemories
        )
    }
}
