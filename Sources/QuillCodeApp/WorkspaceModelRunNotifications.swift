import Foundation
import QuillCodeAgent
import QuillCodeCore
import QuillCodeTools

@MainActor
extension QuillCodeWorkspaceModel {
    /// After a run ends, scan its transcript and stamp the run-integrity verdict
    /// (VERIFIED / UNVERIFIED / RED) onto the run's thread as a persisted notice, so the Activity badge
    /// and the finish notification both read a stable verdict that survives reloads. The thread ID is
    /// explicit so a background completion cannot stamp whichever chat happens to be visible.
    func recordRunIntegrityIfNeeded(outcome: WorkspaceAgentSendTaskOutcome, expectedThreadID: UUID) {
        switch outcome {
        case .completed, .failed: break
        case .cancelled: return
        }
        guard let thread = root.threads.first(where: { $0.id == expectedThreadID }) else { return }
        // Ephemeral threads never surface in Attention and are never persisted — a RED/UNVERIFIED
        // record would otherwise pull the supposedly-hidden thread into the Attention section.
        guard !thread.runtimeContext.isEphemeral else { return }
        mutateThread(expectedThreadID) { thread in
            RunIntegrityRecord.record(into: &thread)
        }
        if let thread = root.threads.first(where: { $0.id == expectedThreadID }) {
            threadPersistence.save(thread)
        }
    }

    /// After a run ends, ping the user if they were away and it needs them: finished,
    /// errored, or blocked on an approval gate. A user-cancelled run is skipped.
    func notifyRunFinishedIfNeeded(outcome: WorkspaceAgentSendTaskOutcome, threadID: UUID) {
        let didFail: Bool
        var budgetStop: AgentRunNotification.BudgetStop?
        switch outcome {
        case .completed(let result):
            didFail = false
            budgetStop = WorkspaceRunNotificationBuilder.budgetStop(for: result.stopReason)
        case .failed: didFail = true
        case .cancelled: return
        }
        guard let handler = onRunNotification,
              let thread = root.threads.first(where: { $0.id == threadID })
        else { return }
        let runProject = thread.projectID.flatMap { projectID in
            root.projects.first { $0.id == projectID }
        }
        let localActions = runProject?.localActions ?? []

        // A ceiling/flail run "gave up" — surface that directly instead of running the verify command
        // and reporting a checked-green finish. Approval/finish runs keep the verification path.
        if let budgetStop {
            postRunNotification(
                thread: thread,
                didFail: false,
                localActions: localActions,
                budgetStop: budgetStop,
                handler: handler
            )
            return
        }

        if let plan = verificationNotificationPlan(
            thread: thread,
            didFail: didFail,
            localActions: localActions,
            workspaceRoot: workspaceRoot(forThreadID: threadID)
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
        localActions: [LocalEnvironmentAction],
        workspaceRoot: URL?
    ) -> (action: LocalEnvironmentAction, workspaceRoot: URL)? {
        guard !didFail,
              WorkspaceTurnRevertPlanner.threadMadeEdits(thread),
              let action = LocalEnvironmentActionMatcher.verificationAction(in: localActions),
              let workspaceRoot else {
            return nil
        }
        return (action, workspaceRoot)
    }

    private func postRunNotification(
        thread: ChatThread,
        didFail: Bool,
        localActions: [LocalEnvironmentAction],
        budgetStop: AgentRunNotification.BudgetStop? = nil,
        handler: @MainActor @Sendable (AgentRunNotification) -> Void
    ) {
        guard let notification = WorkspaceRunNotificationBuilder.notification(
            thread: thread,
            didFail: didFail,
            localActions: localActions,
            budgetStop: budgetStop
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
