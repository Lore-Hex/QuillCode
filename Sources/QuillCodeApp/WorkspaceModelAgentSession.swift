import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
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
        let runProject = sendStart.thread.projectID.flatMap(project(id:))
        let session = agentSendSessionFactory(
            workspaceRoot: workspaceRoot,
            runProject: runProject
        )
            .makeSession(
                prompt: sendStart.prompt,
                thread: sendStart.thread,
                recordsUserMessage: false
            )
        return await AgentRunRetryScope.$threadID.withValue(sendStart.threadID) {
            await WorkspaceAgentSendTaskCoordinator(
                start: sendStart,
                session: session
            ).run { [weak self] progressThread in
                await self?.applyAgentProgress(progressThread, expectedThreadID: sendStart.threadID)
                await onProgressUpdated?()
            }
        }
    }

    /// Turns any self-heals the retry decorator performed during the run (recorded off the main
    /// actor) into visible "Self-healing" thread notices on the run's thread. Drained once the run
    /// ends, not per progress tick, because each tick replaces the thread with the agent's
    /// authoritative copy and would clobber a model-appended notice.
    func drainSelfHealingNotices(expectedThreadID: UUID?) {
        guard let channel = retryEventChannel else { return }
        guard let expectedThreadID else { return }
        let events = channel.drain(threadID: expectedThreadID)
        guard !events.isEmpty,
              root.threads.contains(where: { $0.id == expectedThreadID })
        else { return }
        mutateThread(expectedThreadID) { thread in
            for event in events {
                thread.events.append(ThreadEvent(
                    kind: .notice,
                    summary: SelfHealingNoticePlanner.noticeSummary(attempt: event.attempt, kind: event.kind)
                ))
            }
        }
        if let thread = root.threads.first(where: { $0.id == expectedThreadID }) {
            threadPersistence.save(thread)
        }
    }

    func agentSendSessionFactory(
        workspaceRoot: URL,
        runProject: ProjectRef?
    ) -> WorkspaceAgentSendSessionFactory {
        WorkspaceAgentSendSessionFactory(
            baseRunner: runner,
            selectedProject: runProject,
            config: root.config,
            modelCatalog: root.modelCatalog,
            spendPeriodThreads: root.threads,
            browser: browser,
            browserToolOverride: WorkspaceBrowserAgentToolOverride.make { [weak self] call, workspaceRoot in
                guard let self else { return nil }
                return await self.executeBrowserToolForAgent(call, workspaceRoot: workspaceRoot)
            },
            computerUseBackend: computerUseBackend,
            imageAttachmentStore: imageAttachmentStore,
            globalMemoryDirectory: globalMemoryDirectory,
            mcpToolDefinitions: mcpRuntime.toolDefinitions(
                manifests: runProject?.extensionManifests ?? [],
                extensions: extensions
            ),
            mcpToolExecutionOverride: mcpRuntime.executionOverride(extensions: extensions),
            sshRemoteShellExecutor: sshRemoteShellExecutor,
            permissionRules: permissionRuleStore,
            workspaceRoot: workspaceRoot
        )
    }

    private func executeBrowserToolForAgent(_ call: ToolCall, workspaceRoot: URL) async -> ToolResult? {
        if let result = await visibleBrowserToolOverride?(call, workspaceRoot) {
            refreshTopBar(agentStatus: root.topBar.agentStatus)
            return result
        }

        let result = mutateBrowserState { browser, lastError in
            WorkspaceBrowserToolExecutor.execute(
                call,
                workspaceRoot: workspaceRoot,
                browser: &browser,
                lastError: &lastError,
                domainPolicy: root.config.browserDomainPolicy
            )
        }
        refreshTopBar(agentStatus: root.topBar.agentStatus)
        return result
    }
}
