import Foundation
import QuillCodeAgent
import QuillCodeCore

/// Turns a just-finished agent run (its resulting thread + whether it errored) into an
/// `AgentRunNotification`, so the desktop layer can ping the user when a run they were not watching
/// needs them. Pure + testable: the desktop layer supplies the thread and outcome and posts the OS
/// notification (gated on the app being unfocused).
enum WorkspaceRunNotificationBuilder {
    /// `localActions` are the project's user-authored commands; a `test`/`verify`/`check` one is the
    /// verification gate. `verification` is its result once run (nil until the execution slice wires it,
    /// so an edit-bearing run with a verify action reads as an honest "unverified" rather than a claimed
    /// green).
    static func notification(
        thread: ChatThread,
        didFail: Bool,
        localActions: [LocalEnvironmentAction] = [],
        verification: VerificationVerdict? = nil,
        budgetStop: AgentRunNotification.BudgetStop? = nil
    ) -> AgentRunNotification? {
        let pending = pendingApproval(in: thread)
        // The run-integrity badge is the honesty stamp on the transcript: prefer a verdict already
        // recorded on the thread (stable across reloads), else scan the transcript now.
        let integrity = RunIntegrityRecord.latest(in: thread)?.verdict
            ?? RunIntegrityScanner.verdict(for: thread)
        // A flail stop's reason embeds the first failure-output line — private paths/content that
        // must not reach durable OS notification history from an incognito run. The budget-stop path
        // runs BEFORE the finalAnswer redaction, so it needs its own.
        var budgetStop = budgetStop
        if thread.runtimeContext.isIncognito, case .flailed = budgetStop {
            budgetStop = .flailed(reason: "")
        }
        return AgentRunNotificationPlanner.notification(
            threadTitle: thread.title,
            threadID: thread.id,
            didFail: didFail,
            pendingApprovalSummary: pending?.toolCall.name,
            // Never put incognito reply text into a desktop notification: the OS persists
            // notification history outside the guarded thread store. The finish ping still fires
            // (that's the notify-when-away feature) but with a fixed, content-free body.
            finalAnswer: redactedFinalAnswer(for: thread),
            pendingApprovalRequestID: pending?.id,
            didEditFiles: WorkspaceTurnRevertPlanner.threadMadeEdits(thread),
            hasVerificationAction: LocalEnvironmentActionMatcher.verificationAction(in: localActions) != nil,
            verification: verification,
            budgetStop: budgetStop,
            integrity: integrity
        )
    }

    /// The final-answer text the notification body may carry. For incognito threads the real reply is
    /// replaced with a fixed placeholder whenever one exists — the ping survives, the content doesn't.
    private static func redactedFinalAnswer(for thread: ChatThread) -> String? {
        let answer = thread.messages.last(where: { $0.role == .assistant })?.content
        guard thread.runtimeContext.isIncognito else { return answer }
        guard answer?.isEmpty == false else { return nil }
        return "The reply is ready."
    }

    /// Maps the agent's run stop reason into the App-local `BudgetStop` the notification planner uses —
    /// nil for a genuine finish, and for approval/spend-fuse pauses (those are surfaced by the
    /// pending-approval path, not a "finished run" ping).
    static func budgetStop(for stopReason: AgentRunStopReason) -> AgentRunNotification.BudgetStop? {
        switch stopReason {
        case .toolStepCeilingExhausted(let limit): return .ceilingReached(limit: limit)
        case .flailDetected(let reason): return .flailed(reason: reason)
        case .finished, .spendFuseApprovalRequired, .approvalRequired: return nil
        }
    }

    /// An approval that was requested but never decided means the run stopped waiting on the user —
    /// the most important thing to surface for unattended driving. Its id lets the notification's
    /// Approve/Skip actions decide the exact gate.
    private static func pendingApproval(in thread: ChatThread) -> ApprovalRequest? {
        let decided = Set(thread.events.compactMap { event -> String? in
            guard event.kind == .approvalDecided,
                  let decision: ApprovalDecision = decode(from: event.payloadJSON)
            else {
                return nil
            }
            return decision.requestID
        })
        for event in thread.events.reversed() where event.kind == .approvalRequested {
            guard let request: ApprovalRequest = decode(from: event.payloadJSON),
                  !decided.contains(request.id)
            else {
                continue
            }
            return request
        }
        return nil
    }

    private static func decode<T: Decodable>(from json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
