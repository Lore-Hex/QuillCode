import Foundation
import QuillCodeCore

@MainActor
extension QuillCodeWorkspaceModel {
    func handleSlashCommand(_ command: SlashCommand, originalPrompt: String, workspaceRoot: URL) async {
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

    func runMonitorSlashCommand(_ request: WorkspaceMonitorRequest, originalPrompt: String) {
        appendMonitorAutomationTranscript(
            createMonitorAutomation(request: request),
            userText: originalPrompt
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

    private func appendMonitorAutomationTranscript(
        _ automation: QuillAutomation?,
        userText: String
    ) {
        let transcript = automation
            .map {
                WorkspaceSlashCommandTranscriptPlanner.monitorScheduled(
                    userText: userText,
                    title: $0.title,
                    sourceLabel: $0.scheduleDescription,
                    sourcePath: $0.eventSource?.path ?? ""
                )
            }
            ?? WorkspaceSlashCommandTranscriptPlanner.monitorFailed(
                userText: userText,
                message: lastError
            )
        appendLocalCommandTranscript(transcript)
    }

    private func statusText() -> String {
        WorkspaceStatusTextBuilder.statusText(for: WorkspaceStatusContextBuilder.context(
            root: root,
            selectedProject: selectedProject,
            selectedThread: selectedThread,
            fallbackThreadContext: workspaceThreadContext(root.selectedProjectID)
        ))
    }
}
