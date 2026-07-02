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

    /// All approval requests in the thread that have not been decided yet — the backfill set for a
    /// new "always" rule. Order preserved (oldest first) so backfill resolution is deterministic.
    static func undecidedRequests(in thread: ChatThread?) -> [ApprovalRequest] {
        guard let thread else { return [] }
        var decidedIDs = Set<String>()
        for event in thread.events where event.kind == .approvalDecided {
            if let decision = decode(ApprovalDecision.self, from: event.payloadJSON) {
                decidedIDs.insert(decision.requestID)
            }
        }
        var seenIDs = Set<String>()
        var requests: [ApprovalRequest] = []
        for event in thread.events where event.kind == .approvalRequested {
            guard let request = decode(ApprovalRequest.self, from: event.payloadJSON),
                  !decidedIDs.contains(request.id),
                  seenIDs.insert(request.id).inserted
            else {
                continue
            }
            requests.append(request)
        }
        return requests
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
            rationale: rationale
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
