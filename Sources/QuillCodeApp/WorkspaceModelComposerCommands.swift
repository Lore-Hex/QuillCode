import Foundation
import QuillCodeAgent
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
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

    func executeBrowserToolForAgent(_ call: ToolCall, workspaceRoot: URL) -> ToolResult? {
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

    func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) async {
        let action = WorkspaceSlashCommandDispatchPlanner.action(
            for: command,
            userText: originalPrompt,
            statusText: composerStatusText()
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

    func appendLocalCommandTranscript(_ transcript: WorkspaceLocalCommandTranscript) {
        if selectedThread == nil {
            _ = newChat()
        }
        mutateSelectedThread { thread in
            WorkspaceLocalCommandTranscriptAppender.append(transcript, to: &thread)
        }
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

    private func composerStatusText() -> String {
        WorkspaceStatusTextBuilder.statusText(for: WorkspaceStatusContextBuilder.context(
            root: root,
            selectedProject: selectedProject,
            selectedThread: selectedThread,
            fallbackThreadContext: workspaceThreadContext(root.selectedProjectID)
        ))
    }
}
