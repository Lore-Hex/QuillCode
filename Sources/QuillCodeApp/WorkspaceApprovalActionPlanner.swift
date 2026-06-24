import Foundation
import QuillCodeCore

struct WorkspaceApprovalActionPlan: Sendable, Hashable {
    let request: ApprovalRequest
    let decisionEvent: ThreadEvent
    let shouldRunTool: Bool
    let assistantNotice: String?
}

enum WorkspaceApprovalActionPlanner {
    static func plan(
        action: ToolCardActionSurface,
        thread: ChatThread?
    ) -> WorkspaceApprovalActionPlan? {
        guard let request = pendingRequest(id: action.requestID, in: thread) else {
            return nil
        }
        let decision = ApprovalDecision(
            requestID: action.requestID,
            verdict: verdict(for: action.kind),
            rationale: rationale(for: action.kind)
        )
        return WorkspaceApprovalActionPlan(
            request: request,
            decisionEvent: decisionEvent(for: decision),
            shouldRunTool: action.kind == .approve,
            assistantNotice: action.kind == .deny ? "Skipped \(request.toolCall.name)." : nil
        )
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

    private static func verdict(for kind: ToolCardActionKind) -> ApprovalVerdict {
        switch kind {
        case .approve:
            return .approve
        case .deny:
            return .deny
        }
    }

    private static func rationale(for kind: ToolCardActionKind) -> String {
        switch kind {
        case .approve:
            return "Approved from the tool card."
        case .deny:
            return "Skipped from the tool card."
        }
    }

    private static func decisionEvent(for decision: ApprovalDecision) -> ThreadEvent {
        ThreadEvent(
            kind: .approvalDecided,
            summary: "\(decision.verdict.rawValue): \(decision.rationale)",
            payloadJSON: try? JSONHelpers.encodePretty(decision)
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from payloadJSON: String?) -> T? {
        guard let payloadJSON else { return nil }
        return try? JSONHelpers.decode(type, from: payloadJSON)
    }
}
