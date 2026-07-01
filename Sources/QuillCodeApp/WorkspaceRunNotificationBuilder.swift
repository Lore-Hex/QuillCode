import Foundation
import QuillCodeCore

/// Turns a just-finished agent run (its resulting thread + whether it errored) into an
/// `AgentRunNotification`, so the desktop layer can ping the user when a run they were not watching
/// needs them. Pure + testable: the desktop layer supplies the thread and outcome and posts the OS
/// notification (gated on the app being unfocused).
enum WorkspaceRunNotificationBuilder {
    static func notification(thread: ChatThread, didFail: Bool) -> AgentRunNotification? {
        let pending = pendingApproval(in: thread)
        return AgentRunNotificationPlanner.notification(
            threadTitle: thread.title,
            threadID: thread.id,
            didFail: didFail,
            pendingApprovalSummary: pending?.toolCall.name,
            finalAnswer: thread.messages.last(where: { $0.role == .assistant })?.content,
            pendingApprovalRequestID: pending?.id
        )
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
