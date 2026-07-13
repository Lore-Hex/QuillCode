import Foundation
import QuillCodeCore

enum WorkspaceSubagentApprovalPayloadResolver {
    static func payload(
        for request: ApprovalRequest,
        heldToolCall: ToolCall?
    ) throws -> ToolCall {
        switch request.scope {
        case .tool:
            guard let heldToolCall,
                  matches(heldToolCall, request.toolCall)
            else {
                throw WorkspaceSubagentApprovalPayloadError.missingOrMismatchedToolCall
            }
            return heldToolCall
        case .runSpendFuse:
            return request.toolCall
        }
    }

    static func matches(_ payload: ToolCall, _ presentedCall: ToolCall) -> Bool {
        payload.id == presentedCall.id && payload.name == presentedCall.name
    }
}

enum WorkspaceSubagentApprovalPayloadError: LocalizedError {
    case missingOrMismatchedToolCall

    var errorDescription: String? {
        "The protected delegated action no longer matches its approval request."
    }
}
