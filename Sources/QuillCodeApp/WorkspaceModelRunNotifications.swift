import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    /// After a run ends, ping the user if they were away and it needs them: finished,
    /// errored, or blocked on an approval gate. A user-cancelled run is skipped.
    func notifyRunFinishedIfNeeded(outcome: WorkspaceAgentSendTaskOutcome) {
        let didFail: Bool
        switch outcome {
        case .completed: didFail = false
        case .failed: didFail = true
        case .cancelled: return
        }
        guard let handler = onRunNotification, let thread = selectedThread else { return }
        let localActions = selectedProject?.localActions ?? []

        if let plan = verificationNotificationPlan(
            thread: thread,
            didFail: didFail,
            localActions: localActions
        ) {
            Task { [weak self, handler] in
                await self?.runVerificationAndNotify(
                    action: plan.action,
                    thread: thread,
                    localActions: localActions,
                    workspaceRoot: plan.workspaceRoot,
                    handler: handler
                )
            }
            return
        }

        postRunNotification(
            thread: thread,
            didFail: didFail,
            localActions: localActions,
            handler: handler
        )
    }

    private func verificationNotificationPlan(
        thread: ChatThread,
        didFail: Bool,
        localActions: [LocalEnvironmentAction]
    ) -> (action: LocalEnvironmentAction, workspaceRoot: URL)? {
        guard !didFail,
              WorkspaceTurnRevertPlanner.threadMadeEdits(thread),
              let action = LocalEnvironmentActionMatcher.verificationAction(in: localActions),
              let workspaceRoot = activeWorkspaceRoot else {
            return nil
        }
        return (action, workspaceRoot)
    }

    private func postRunNotification(
        thread: ChatThread,
        didFail: Bool,
        localActions: [LocalEnvironmentAction],
        handler: @MainActor @Sendable (AgentRunNotification) -> Void
    ) {
        guard let notification = WorkspaceRunNotificationBuilder.notification(
            thread: thread,
            didFail: didFail,
            localActions: localActions
        ) else {
            return
        }
        handler(notification)
    }

    /// Runs the project's verify command off the main actor through the injected or
    /// default runner, then posts the CHECKED notification with the resulting verdict.
    func runVerificationAndNotify(
        action: LocalEnvironmentAction,
        thread: ChatThread,
        localActions: [LocalEnvironmentAction],
        workspaceRoot: URL,
        handler: @MainActor @Sendable (AgentRunNotification) -> Void
    ) async {
        let runner = verificationRunner ?? Self.runVerificationCommandViaShell
        let verdict = VerificationResultParser.parse(await runner(action, workspaceRoot))
        guard let notification = WorkspaceRunNotificationBuilder.notification(
            thread: thread,
            didFail: false,
            localActions: localActions,
            verification: verdict
        ) else {
            return
        }
        handler(notification)
    }

    static func runVerificationCommandViaShell(
        _ action: LocalEnvironmentAction,
        _ workspaceRoot: URL
    ) async -> ToolResult {
        let cwd = action.workingDirectory
            .map { workspaceRoot.appendingPathComponent($0) }
            ?? workspaceRoot
        let request = ShellExecutionRequest(
            command: action.command,
            cwd: cwd,
            timeoutSeconds: TimeInterval(action.timeoutSeconds ?? 120),
            environment: action.environment
        )
        return await ShellToolExecutor().runCancellable(request)
    }
}
