import Foundation
import QuillCodeCore

struct WorkspaceApprovalActionPlan: Sendable, Hashable {
    let request: ApprovalRequest
    let decisionEvent: ThreadEvent?
    let shouldRunTool: Bool
    let assistantNotice: String?
    let composerDraft: String?
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
        assistantNotice: String?
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
            composerDraft: nil
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
