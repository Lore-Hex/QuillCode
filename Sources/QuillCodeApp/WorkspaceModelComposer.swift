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

    public func submitComposer(workspaceRoot: URL) async {
        let submissionPlan = WorkspaceComposerSubmissionPlanner.plan(draft: composer.draft)
        let prompt: String
        switch submissionPlan {
        case .ignore:
            return
        case .slash(let command, let originalPrompt):
            composer.draft = ""
            setLastError(nil)
            handleSlashCommand(command, originalPrompt: originalPrompt, workspaceRoot: workspaceRoot)
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
        applyComposerSendLifecycle(sendStart.lifecycle)

        let session = agentSendSessionFactory(workspaceRoot: workspaceRoot)
            .makeSession(prompt: sendStart.prompt, thread: sendStart.thread)
        let outcome = await WorkspaceAgentSendTaskCoordinator(
            start: sendStart,
            session: session
        ).run { [weak self] progressThread in
            await self?.applyAgentProgress(progressThread, expectedThreadID: sendStart.threadID)
        }
        finishAgentSend(outcome)
    }

    private func prepareAgentSendThread() -> ChatThread? {
        if selectedThread == nil {
            _ = newChat()
        }
        guard var thread = selectedThread else { return nil }
        syncThreadContext(into: &thread)
        return thread
    }

    private func agentSendSessionFactory(workspaceRoot: URL) -> WorkspaceAgentSendSessionFactory {
        WorkspaceAgentSendSessionFactory(
            baseRunner: runner,
            selectedProject: selectedProject,
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
        applyComposerSendLifecycle(completion.lifecycle)
    }

    private func finishAgentSend(_ outcome: WorkspaceAgentSendTaskOutcome) {
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

    private func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) {
        let action = WorkspaceSlashCommandDispatchPlanner.action(
            for: command,
            userText: originalPrompt,
            statusText: statusText()
        )
        runSlashCommandDispatchAction(action, workspaceRoot: workspaceRoot)
        composer.isSending = false
        refreshTopBar(agentStatus: TopBarAgentStatusLabel.idle)
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
