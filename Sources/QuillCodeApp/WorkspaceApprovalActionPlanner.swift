import Foundation
import QuillCodeCore
import QuillCodeSafety

struct WorkspaceApprovalActionPlan: Sendable, Hashable {
    let request: ApprovalRequest
    let decisionEvent: ThreadEvent?
    let shouldRunTool: Bool
    let assistantNotice: String?
    let composerDraft: String?
    /// Non-nil for the "always" answers: persist a permission rule with this decision (derived
    /// from `request`) and backfill other pending requests the new rule matches.
    let persistRuleDecision: PermissionRuleDecision?

    init(
        request: ApprovalRequest,
        decisionEvent: ThreadEvent?,
        shouldRunTool: Bool,
        assistantNotice: String?,
        composerDraft: String?,
        persistRuleDecision: PermissionRuleDecision? = nil
    ) {
        self.request = request
        self.decisionEvent = decisionEvent
        self.shouldRunTool = shouldRunTool
        self.assistantNotice = assistantNotice
        self.composerDraft = composerDraft
        self.persistRuleDecision = persistRuleDecision
    }
}

enum WorkspaceApprovalActionPlanner {
    static func plan(
        action: ToolCardActionSurface,
        thread: ChatThread?
    ) -> WorkspaceApprovalActionPlan? {
        guard let request = pendingRequest(id: action.requestID, in: thread) else {
            return nil
        }
        if request.scope == .runSpendFuse {
            return spendFusePlan(action: action, request: request)
        }
        switch action.kind {
        case .approve:
            return decisionPlan(
                request: request,
                verdict: .approve,
                rationale: "Approved from the tool card.",
                shouldRunTool: true,
                assistantNotice: nil
            )
        case .edit:
            return WorkspaceApprovalActionPlan(
                request: request,
                decisionEvent: nil,
                shouldRunTool: false,
                assistantNotice: nil,
                composerDraft: WorkspaceApprovalEditDraftBuilder.draft(for: request)
            )
        case .deny:
            return decisionPlan(
                request: request,
                verdict: .deny,
                rationale: "Skipped from the tool card.",
                shouldRunTool: false,
                assistantNotice: "Skipped \(request.toolCall.name)."
            )
        case .approveAlways:
            return decisionPlan(
                request: request,
                verdict: .approve,
                rationale: "Approved from the tool card and saved as an always-allow rule.",
                shouldRunTool: true,
                assistantNotice: nil,
                persistRuleDecision: .allow
            )
        case .denyAlways:
            return decisionPlan(
                request: request,
                verdict: .deny,
                rationale: "Skipped from the tool card and saved as an always-deny rule.",
                shouldRunTool: false,
                assistantNotice: "Skipped \(request.toolCall.name) and saved a rule to keep blocking it.",
                persistRuleDecision: .deny
            )
        }
    }

    private static func spendFusePlan(
        action: ToolCardActionSurface,
        request: ApprovalRequest
    ) -> WorkspaceApprovalActionPlan? {
        switch action.kind {
        case .approve:
            return decisionPlan(
                request: request,
                verdict: .approve,
                rationale: "Approved spend-fuse continuation from the tool card.",
                shouldRunTool: false,
                assistantNotice: nil
            )
        case .deny:
            return decisionPlan(
                request: request,
                verdict: .deny,
                rationale: "Stopped at the spend fuse from the tool card.",
                shouldRunTool: false,
                assistantNotice: "Stopped before spending more on this thread."
            )
        case .edit, .approveAlways, .denyAlways:
            return nil
        }
    }

    static func pendingRequest(id: String, in thread: ChatThread?) -> ApprovalRequest? {
        thread?.events.lazy.compactMap { event -> ApprovalRequest? in
            guard event.kind == .approvalRequested,
                  let request = decode(ApprovalRequest.self, from: event.payloadJSON),
                  request.id == id
            else {
                return nil
            }
            return request
        }.last
    }

    /// Undecided approval requests from the CURRENT turn — the backfill set for a new "always" rule.
    ///
    /// Backfill only resolves requests the user has NOT implicitly abandoned. A request from an
    /// earlier turn (the user sent a new message after it without deciding it, redirecting) is
    /// stale: re-running it now could clobber current state with a week-old write. So the set is
    /// bounded to requests that appear AFTER the last user message in the event stream. Order is
    /// preserved (oldest first) so resolution is deterministic.
    static func undecidedRequests(in thread: ChatThread?) -> [ApprovalRequest] {
        guard let thread else { return [] }
        let turnStartIndex = currentTurnStartIndex(in: thread)
        var decidedIDs = Set<String>()
        for event in thread.events where event.kind == .approvalDecided {
            if let decision = decode(ApprovalDecision.self, from: event.payloadJSON) {
                decidedIDs.insert(decision.requestID)
            }
        }
        var seenIDs = Set<String>()
        var requests: [ApprovalRequest] = []
        for index in thread.events.indices where index >= turnStartIndex {
            let event = thread.events[index]
            guard event.kind == .approvalRequested,
                  let request = decode(ApprovalRequest.self, from: event.payloadJSON),
                  !decidedIDs.contains(request.id),
                  seenIDs.insert(request.id).inserted
            else {
                continue
            }
            requests.append(request)
        }
        return requests
    }

    /// The event index at which the current turn begins: just after the last user-authored message
    /// event. Requests before it belong to earlier turns the user moved on from. When no user
    /// message is found (e.g. a synthetic thread in tests), the whole thread is the current turn.
    private static func currentTurnStartIndex(in thread: ChatThread) -> Int {
        // The most recent user message content; user messages carry it verbatim into a `.message`
        // event summary, so we locate that event's last occurrence.
        guard let lastUserMessage = thread.messages.last(where: { $0.role == .user })?.content else {
            return 0
        }
        for index in thread.events.indices.reversed() {
            let event = thread.events[index]
            if event.kind == .message, event.summary == lastUserMessage {
                return index + 1
            }
        }
        return 0
    }

    private static func decisionEvent(for decision: ApprovalDecision) -> ThreadEvent {
        ThreadEvent(
            kind: .approvalDecided,
            summary: "\(decision.verdict.rawValue): \(decision.rationale)",
            payloadJSON: try? JSONHelpers.encodePretty(decision)
        )
    }

    private static func decisionPlan(
        request: ApprovalRequest,
        verdict: ApprovalVerdict,
        rationale: String,
        shouldRunTool: Bool,
        assistantNotice: String?,
        persistRuleDecision: PermissionRuleDecision? = nil
    ) -> WorkspaceApprovalActionPlan {
        let decision = ApprovalDecision(
            requestID: request.id,
            verdict: verdict,
            rationale: rationale,
            reviewTelemetry: request.reviewTelemetry
        )
        return WorkspaceApprovalActionPlan(
            request: request,
            decisionEvent: decisionEvent(for: decision),
            shouldRunTool: shouldRunTool,
            assistantNotice: assistantNotice,
            composerDraft: nil,
            persistRuleDecision: persistRuleDecision
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}

private enum WorkspaceApprovalEditDraftBuilder {
    static func draft(for request: ApprovalRequest) -> String {
        let toolCall = request.toolCall
        if let command = shellCommand(in: toolCall) {
            return "Run \(command)"
        }
        return """
        Revise and run \(toolCall.name) with arguments:
        \(toolCall.argumentsJSON)
        """
    }

    private static func shellCommand(in toolCall: ToolCall) -> String? {
        guard toolCall.name == "host.shell.run",
              let arguments = try? ToolArguments(toolCall.argumentsJSON),
              let command = arguments.string("cmd")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty
        else {
            return nil
        }
        return command
    }
}
